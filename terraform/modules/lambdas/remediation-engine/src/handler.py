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
- No deletion of production resources (logic handled in Policy Engine or here)
"""

import json
import logging
import os
import boto3
from botocore.exceptions import ClientError
from typing import Any, Dict

# Configure logging
log_level = os.environ.get("LOG_LEVEL", "INFO")
logger = logging.getLogger()
logger.setLevel(getattr(logging, log_level))

# Environment variables
REMEDIATION_ROLE_NAME = os.environ.get("REMEDIATION_ROLE_NAME", "CloudGovernanceRemediationRole")
EXTERNAL_ID = os.environ.get("EXTERNAL_ID", "CloudGovernance-Remediation-2024")

STS_CLIENT = boto3.client("sts")

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
    
    if not all([account_id, rule_name, resource_id, region]):
        logger.error("Missing required fields in compliance data")
        return {"statusCode": 400, "body": "Missing required fields"}
    
    try:
        # 1. Assume Role in Target Account
        logger.info(f"Assuming role {REMEDIATION_ROLE_NAME} in account {account_id}")
        session = assume_role(account_id, region)
        
        # 2. Execute Remediation
        if rule_name == "s3-bucket-public-read-prohibited":
            remediate_s3_public_read(session, resource_id)
        elif rule_name == "s3-bucket-public-write-prohibited":
            remediate_s3_public_write(session, resource_id)
        elif rule_name == "required-tags":
            remediate_required_tags(session, resource_id, compliance_data.get("resource_type", ""))
        else:
            logger.warning(f"No remediation logic defined for rule: {rule_name}")
            return {"statusCode": 200, "body": f"No remediation defined for {rule_name}"}
            
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": f"Successfully remediated {rule_name} on {resource_id}",
                "resource_id": resource_id,
                "account_id": account_id
            })
        }
        
    except ClientError as e:
        logger.error(f"AWS Error during remediation: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        raise


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
    
    # Enable Public Access Block
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
    Remediate public write access on S3 bucket (same as public read for now).
    """
    logger.info(f"Remediating S3 public write on {bucket_name}")
    remediate_s3_public_read(session, bucket_name)


def remediate_required_tags(session: boto3.Session, resource_id: str, resource_type: str):
    """
    Add placeholder tags for missing required tags.
    """
    logger.info(f"Remediating missing tags on {resource_id} ({resource_type})")
    
    tags_to_add = [
        {'Key': 'Owner', 'Value': 'PlatformOps'},
        {'Key': 'CostCenter', 'Value': '0000'},
        {'Key': 'Project', 'Value': 'GovernanceRemediation'},
        {'Key': 'Environment', 'Value': 'Production'}, # Default fallback
    ]
    
    if resource_type == "AWS::EC2::Instance":
        ec2 = session.client("ec2")
        ec2.create_tags(Resources=[resource_id], Tags=tags_to_add)
    
    elif resource_type == "AWS::S3::Bucket":
        s3 = session.client("s3")
        # S3 tagging replaces all tags, so we need to fetch existing ones first
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

    elif resource_type == "AWS::DynamoDB::Table":
        ddb = session.client("dynamodb")
        # Construct ARN since config event gives table name for resourceId usually
        # ARN format: arn:aws:dynamodb:region:account-id:table/tablename
        # We need the account ID and region from the session or passed in context
        # But we can get region from session.
        # Wait, resource_id IS the resource name for DynamoDB in Config events usually.
        # Let's assume resource_id is the table name.
        # But for tag_resource we need the ARN.
        
        # We need account_id to construct ARN. It's not passed into this function signature yet.
        # However, we are running IN the target account (after assume role).
        # We can get the account ID from sts.get_caller_identity or pass it in.
        
        # It's better to update the signature if possible, OR assume the calling session acts on its own account.
        # The session is constructed for the target account. 
        # So we can get the ARN using the session's region and identity.
        
        sts = session.client("sts")
        account_id = sts.get_caller_identity()["Account"]
        region = session.region_name
        resource_arn = f"arn:aws:dynamodb:{region}:{account_id}:table/{resource_id}"
        
        ddb.tag_resource(ResourceArn=resource_arn, Tags=tags_to_add)
        
    else:
        logger.warning(f"Tag remediation not implemented for resource type: {resource_type}")

