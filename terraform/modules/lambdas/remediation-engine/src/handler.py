"""
Remediation Engine Lambda Handler
=================================
Performs auto-remediation actions in member accounts.

Responsibilities:
1. Receive remediation request from Policy Engine
2. Assume cross-account role in the target member account
3. Execute safe remediation logic based on the violated rule
4. Log all actions for audit purposes

Safety Guardrails:
- Only executes known, safe remediation actions
- Requires explicit external ID for role assumption
- Security Group remediation blocked in production (notify instead)
- Environment-aware default tagging based on account ID
"""

import json
import logging
import os
import boto3
from botocore.exceptions import ClientError
from typing import Any, Dict, List
from urllib.request import Request, urlopen
from urllib.error import URLError

# Configure logging
log_level = os.environ.get("LOG_LEVEL", "INFO")
logger = logging.getLogger()
logger.setLevel(getattr(logging, log_level))

# Environment variables
REMEDIATION_ROLE_NAME = os.environ.get("REMEDIATION_ROLE_NAME", "CloudGovernanceRemediationRole")
EXTERNAL_ID = os.environ.get("EXTERNAL_ID", "CloudGovernance-Remediation-2024")
NOTIFICATION_LAMBDA = os.environ.get("NOTIFICATION_LAMBDA", "")

# Account to Environment mapping (passed via environment variable)
ACCOUNT_ENVIRONMENT_MAP = json.loads(os.environ.get("ACCOUNT_ENVIRONMENT_MAP", "{}"))

# Production account ID for safety checks
PROD_ACCOUNT_ID = os.environ.get("PROD_ACCOUNT_ID", "")

# Environment-specific default tags
DEFAULT_TAGS_BY_ENV = {
    "dev": {
        "Owner": "Platform-Engineering",
        "CostCenter": "DEV-001",
        "Project": "CloudGovernancePlatform",
        "Environment": "dev",
        "ManagedBy": "Terraform"
    },
    "staging": {
        "Owner": "Platform-Engineering",
        "CostCenter": "STG-001",
        "Project": "CloudGovernancePlatform",
        "Environment": "staging",
        "ManagedBy": "Terraform"
    },
    "prod": {
        "Owner": "Platform-Engineering",
        "CostCenter": "PROD-001",
        "Project": "CloudGovernancePlatform",
        "Environment": "prod",
        "ManagedBy": "Terraform"
    },
    "governance": {
        "Owner": "Platform-Engineering",
        "CostCenter": "INFRA-001",
        "Project": "CloudGovernancePlatform",
        "Environment": "governance",
        "ManagedBy": "Terraform"
    },
    "tooling": {
        "Owner": "Platform-Engineering",
        "CostCenter": "CICD-001",
        "Project": "CloudGovernancePlatform",
        "Environment": "tooling",
        "ManagedBy": "Terraform"
    }
}

# Fallback tags if environment not found
DEFAULT_TAGS_FALLBACK = {
    "Owner": "Platform-Engineering",
    "CostCenter": "UNKNOWN-001",
    "Project": "CloudGovernancePlatform",
    "Environment": "unknown",
    "ManagedBy": "Terraform"
}

STS_CLIENT = boto3.client("sts")
LAMBDA_CLIENT = boto3.client("lambda")


def lambda_handler(event: dict, context: Any) -> dict:
    """
    Main entry point for remediation.
    """
    logger.info(f"Received remediation request: {json.dumps(event)}")
    
    action = event.get("action")
    if action != "remediate":
        logger.warning(f"Unknown action: {action}")
        return {"statusCode": 400, "body": "Unknown action"}
    
    compliance_data = event.get("compliance_data", {})
    account_id = compliance_data.get("account_id")
    rule_name = compliance_data.get("rule_name")
    resource_id = compliance_data.get("resource_id")
    region = compliance_data.get("region")
    resource_type = compliance_data.get("resource_type", "")
    
    if not all([account_id, rule_name, resource_id, region]):
        logger.error("Missing required fields in compliance data")
        return {"statusCode": 400, "body": "Missing required fields"}
    
    # Determine environment from account ID
    environment = get_environment_for_account(account_id)
    logger.info(f"Account {account_id} mapped to environment: {environment}")
    
    # Production safety check for Security Group remediation
    if rule_name in ["restricted-ssh", "restricted-rdp"]:
        if is_production_account(account_id):
            logger.warning(f"Security Group remediation blocked in production. Sending notification instead.")
            notify_instead_of_remediate(compliance_data, "Production safety: SG remediation blocked")
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "message": "Production safety: Notification sent instead of remediation",
                    "rule_name": rule_name,
                    "account_id": account_id
                })
            }
    
    try:
        # 1. Assume Role in Target Account
        logger.info(f"Assuming role {REMEDIATION_ROLE_NAME} in account {account_id}")
        session = assume_role(account_id, region)
        
        # 2. Execute Remediation based on rule
        if rule_name == "s3-bucket-public-read-prohibited":
            remediate_s3_public_read(session, resource_id)
        elif rule_name == "s3-bucket-level-public-access-prohibited":
            # Enforce BPA is always ON (same remediation as public-read)
            remediate_s3_public_read(session, resource_id)
        elif rule_name == "s3-bucket-public-write-prohibited":
            remediate_s3_public_write(session, resource_id)
        elif rule_name == "required-tags":
            remediate_required_tags(session, resource_id, resource_type, account_id, environment)
        elif rule_name in ["restricted-ssh", "restricted-rdp"]:
            remediate_security_group(session, resource_id, rule_name)
        else:
            logger.warning(f"No remediation logic defined for rule: {rule_name}")
            return {"statusCode": 200, "body": f"No remediation defined for {rule_name}"}
            
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": f"Successfully remediated {rule_name} on {resource_id}",
                "resource_id": resource_id,
                "account_id": account_id,
                "environment": environment
            })
        }
        
    except ClientError as e:
        logger.error(f"AWS Error during remediation: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        raise


def get_environment_for_account(account_id: str) -> str:
    """
    Get the environment name for an account ID.
    Returns 'unknown' if account is not in the mapping.
    """
    return ACCOUNT_ENVIRONMENT_MAP.get(account_id, "unknown")


def is_production_account(account_id: str) -> bool:
    """
    Check if an account is the production account.
    """
    # Check via explicit PROD_ACCOUNT_ID env var
    if PROD_ACCOUNT_ID and account_id == PROD_ACCOUNT_ID:
        return True
    # Check via account mapping
    return get_environment_for_account(account_id) == "prod"


def notify_instead_of_remediate(compliance_data: dict, reason: str) -> None:
    """
    Send a notification instead of remediating (for prod safety).
    """
    if not NOTIFICATION_LAMBDA:
        logger.warning("Notification Lambda not configured, cannot notify")
        return
    
    payload = {
        "action": "notify",
        "compliance_data": {
            **compliance_data,
            "severity": "HIGH",  # Escalate to HIGH since we're not remediating
            "annotation": f"{reason}. Manual intervention required."
        }
    }
    
    try:
        LAMBDA_CLIENT.invoke(
            FunctionName=NOTIFICATION_LAMBDA,
            InvocationType="Event",
            Payload=json.dumps(payload)
        )
        logger.info(f"Sent notification instead of remediation: {reason}")
    except ClientError as e:
        logger.error(f"Failed to invoke notification Lambda: {e}")


def assume_role(account_id: str, region: str) -> boto3.Session:
    """
    Assume the remediation role in the target account.
    """
    role_arn = f"arn:aws:iam::{account_id}:role/{REMEDIATION_ROLE_NAME}"
    
    try:
        response = STS_CLIENT.assume_role(
            RoleArn=role_arn,
            RoleSessionName="GovernanceRemediationEngine",
            ExternalId=EXTERNAL_ID
        )
        
        credentials = response["Credentials"]
        
        return boto3.Session(
            aws_access_key_id=credentials["AccessKeyId"],
            aws_secret_access_key=credentials["SecretAccessKey"],
            aws_session_token=credentials["SessionToken"],
            region_name=region
        )
    except ClientError as e:
        logger.error(f"Failed to assume role {role_arn}: {e}")
        raise


def remediate_s3_public_read(session: boto3.Session, bucket_name: str):
    """
    Remediate public read access on S3 bucket.
    """
    logger.info(f"Remediating S3 public read on {bucket_name}")
    s3 = session.client("s3")
    
    try:
        s3.put_public_access_block(
            Bucket=bucket_name,
            PublicAccessBlockConfiguration={
                'BlockPublicAcls': True,
                'IgnorePublicAcls': True,
                'BlockPublicPolicy': True,
                'RestrictPublicBuckets': True
            }
        )
        logger.info(f"Enabled Public Access Block on {bucket_name}")
    except ClientError as e:
        logger.error(f"Failed to enable S3 Public Access Block: {e}")
        raise


def remediate_s3_public_write(session: boto3.Session, bucket_name: str):
    """
    Remediate public write access on S3 bucket (same as public read).
    """
    logger.info(f"Remediating S3 public write on {bucket_name}")
    remediate_s3_public_read(session, bucket_name)


def remediate_security_group(session: boto3.Session, security_group_id: str, rule_name: str):
    """
    Remediate security group by revoking dangerous ingress rules.
    
    For restricted-ssh: Revoke rules allowing 0.0.0.0/0 on port 22
    For restricted-rdp: Revoke rules allowing 0.0.0.0/0 on port 3389
    """
    logger.info(f"Remediating security group {security_group_id} for rule {rule_name}")
    ec2 = session.client("ec2")
    
    # Determine which port to check based on rule
    target_port = 22 if rule_name == "restricted-ssh" else 3389
    dangerous_cidrs = ["0.0.0.0/0", "::/0"]
    
    try:
        # Get current security group rules
        response = ec2.describe_security_groups(GroupIds=[security_group_id])
        
        if not response.get("SecurityGroups"):
            logger.warning(f"Security group {security_group_id} not found")
            return
        
        sg = response["SecurityGroups"][0]
        rules_to_revoke = []
        
        for rule in sg.get("IpPermissions", []):
            # Check if this rule applies to the target port
            from_port = rule.get("FromPort", 0)
            to_port = rule.get("ToPort", 0)
            
            # Check if target port is within the range
            if from_port is not None and to_port is not None:
                if not (from_port <= target_port <= to_port):
                    continue
            
            # Check for dangerous IP ranges
            for ip_range in rule.get("IpRanges", []):
                if ip_range.get("CidrIp") in dangerous_cidrs:
                    rules_to_revoke.append({
                        "IpProtocol": rule.get("IpProtocol", "tcp"),
                        "FromPort": from_port,
                        "ToPort": to_port,
                        "IpRanges": [{"CidrIp": ip_range.get("CidrIp")}]
                    })
                    logger.info(f"Found dangerous rule: {ip_range.get('CidrIp')} on port {target_port}")
            
            # Check for IPv6 ranges
            for ip_range in rule.get("Ipv6Ranges", []):
                if ip_range.get("CidrIpv6") in dangerous_cidrs:
                    rules_to_revoke.append({
                        "IpProtocol": rule.get("IpProtocol", "tcp"),
                        "FromPort": from_port,
                        "ToPort": to_port,
                        "Ipv6Ranges": [{"CidrIpv6": ip_range.get("CidrIpv6")}]
                    })
                    logger.info(f"Found dangerous IPv6 rule: {ip_range.get('CidrIpv6')} on port {target_port}")
        
        # Revoke the dangerous rules
        if rules_to_revoke:
            for rule in rules_to_revoke:
                ec2.revoke_security_group_ingress(
                    GroupId=security_group_id,
                    IpPermissions=[rule]
                )
                logger.info(f"Revoked ingress rule from {security_group_id}: {json.dumps(rule)}")
            
            logger.info(f"Successfully remediated {len(rules_to_revoke)} rules on {security_group_id}")
        else:
            logger.info(f"No dangerous rules found on {security_group_id} for port {target_port}")
            
    except ClientError as e:
        logger.error(f"Failed to remediate security group {security_group_id}: {e}")
        raise


def get_tags_for_environment(environment: str) -> List[Dict[str, str]]:
    """
    Get the default tags for a specific environment.
    Returns a list of tag dicts suitable for AWS APIs.
    """
    tag_dict = DEFAULT_TAGS_BY_ENV.get(environment, DEFAULT_TAGS_FALLBACK)
    return [{"Key": k, "Value": v} for k, v in tag_dict.items()]


def remediate_required_tags(
    session: boto3.Session, 
    resource_id: str, 
    resource_type: str,
    account_id: str,
    environment: str
):
    """
    Add environment-aware default tags for missing required tags.
    """
    logger.info(f"Remediating missing tags on {resource_id} ({resource_type}) in {environment} environment")
    
    # Get environment-specific tags
    tags_to_add = get_tags_for_environment(environment)
    logger.info(f"Using tags for environment '{environment}': {json.dumps(tags_to_add)}")
    
    if resource_type == "AWS::EC2::Instance":
        ec2 = session.client("ec2")
        # EC2 create_tags merges by default, won't overwrite existing
        ec2.create_tags(Resources=[resource_id], Tags=tags_to_add)
        logger.info(f"Added tags to EC2 instance {resource_id}")
    
    elif resource_type == "AWS::S3::Bucket":
        s3 = session.client("s3")
        # S3 tagging replaces all tags, so fetch existing ones first
        try:
            current_tags = s3.get_bucket_tagging(Bucket=resource_id).get('TagSet', [])
        except ClientError as e:
            if "NoSuchTagSet" in str(e):
                current_tags = []
            else:
                raise
        
        # Merge tags (don't overwrite existing keys)
        existing_keys = {t['Key'] for t in current_tags}
        new_tags = current_tags + [t for t in tags_to_add if t['Key'] not in existing_keys]
        
        s3.put_bucket_tagging(Bucket=resource_id, Tagging={'TagSet': new_tags})
        logger.info(f"Added tags to S3 bucket {resource_id}")

    elif resource_type == "AWS::DynamoDB::Table":
        ddb = session.client("dynamodb")
        sts = session.client("sts")
        caller_account_id = sts.get_caller_identity()["Account"]
        region = session.region_name
        resource_arn = f"arn:aws:dynamodb:{region}:{caller_account_id}:table/{resource_id}"
        
        ddb.tag_resource(ResourceArn=resource_arn, Tags=tags_to_add)
        logger.info(f"Added tags to DynamoDB table {resource_id}")
    
    elif resource_type == "AWS::Lambda::Function":
        lambda_client = session.client("lambda")
        # Lambda tag_resource uses a dict, not list
        tag_dict = {t['Key']: t['Value'] for t in tags_to_add}
        lambda_client.tag_resource(Resource=resource_id, Tags=tag_dict)
        logger.info(f"Added tags to Lambda function {resource_id}")
    
    elif resource_type == "AWS::RDS::DBInstance":
        rds = session.client("rds")
        # RDS uses add_tags_to_resource
        rds.add_tags_to_resource(ResourceName=resource_id, Tags=tags_to_add)
        logger.info(f"Added tags to RDS instance {resource_id}")
    
    elif resource_type == "AWS::EC2::SecurityGroup":
        ec2 = session.client("ec2")
        ec2.create_tags(Resources=[resource_id], Tags=tags_to_add)
        logger.info(f"Added tags to Security Group {resource_id}")
        
    else:
        logger.warning(f"Tag remediation not implemented for resource type: {resource_type}")
