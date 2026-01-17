"""
Drift Detection Lambda Handler
==============================
Detects configuration drift between Terraform state and actual AWS resources.

Flow:
1. Reads Terraform state from S3 backend
2. Queries AWS Config for current resource state
3. Compares key attributes
4. Alerts on mismatches via SNS + Slack

Schedule: Daily at 7pm UTC (configurable via EventBridge)
"""

import json
import logging
import os
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.exceptions import ClientError

# Configure logging
log_level = os.environ.get("LOG_LEVEL", "INFO")
logger = logging.getLogger()
logger.setLevel(getattr(logging, log_level))

# AWS clients
s3 = boto3.client("s3")
config_client = boto3.client("config")
lambda_client = boto3.client("lambda")

# Environment variables
TF_STATE_BUCKET = os.environ.get("TF_STATE_BUCKET", "")
TF_STATE_KEY = os.environ.get("TF_STATE_KEY", "governance/terraform.tfstate")
NOTIFICATION_LAMBDA = os.environ.get("NOTIFICATION_LAMBDA", "")
ACCOUNTS_TO_CHECK = json.loads(os.environ.get("ACCOUNTS_TO_CHECK", "[]"))


def lambda_handler(event: dict, context: Any) -> dict:
    """
    Main entry point for drift detection.
    Triggered by EventBridge schedule.
    """
    logger.info(f"Starting drift detection at {datetime.now(timezone.utc).isoformat()}")
    logger.info(f"Event: {json.dumps(event)}")
    
    try:
        # Load Terraform state
        tf_state = load_terraform_state()
        if not tf_state:
            return {"statusCode": 500, "body": "Failed to load Terraform state"}
        
        # Extract managed resources from state
        managed_resources = extract_managed_resources(tf_state)
        logger.info(f"Found {len(managed_resources)} managed resources in Terraform state")
        
        # Check each resource for drift
        drift_results = []
        for resource in managed_resources:
            drift = check_resource_drift(resource)
            if drift:
                drift_results.append(drift)
        
        # Report results
        if drift_results:
            logger.warning(f"Detected {len(drift_results)} drifted resources")
            send_drift_alert(drift_results)
        else:
            logger.info("No drift detected - all resources match Terraform state")
        
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Drift detection completed",
                "resources_checked": len(managed_resources),
                "drift_detected": len(drift_results),
                "drifted_resources": [d["resource_id"] for d in drift_results]
            })
        }
        
    except Exception as e:
        logger.error(f"Drift detection failed: {e}", exc_info=True)
        return {"statusCode": 500, "body": str(e)}


def load_terraform_state() -> dict | None:
    """Load Terraform state file from S3."""
    if not TF_STATE_BUCKET:
        logger.error("TF_STATE_BUCKET not configured")
        return None
    
    try:
        response = s3.get_object(
            Bucket=TF_STATE_BUCKET,
            Key=TF_STATE_KEY
        )
        state = json.loads(response["Body"].read().decode("utf-8"))
        logger.info(f"Loaded Terraform state version {state.get('version', 'unknown')}")
        return state
        
    except ClientError as e:
        if e.response["Error"]["Code"] == "NoSuchKey":
            logger.error(f"Terraform state not found: s3://{TF_STATE_BUCKET}/{TF_STATE_KEY}")
        else:
            logger.error(f"Failed to load Terraform state: {e}")
        return None


def extract_managed_resources(state: dict) -> list[dict]:
    """Extract resource information from Terraform state."""
    resources = []
    
    # Terraform 1.0+ format
    for resource_block in state.get("resources", []):
        resource_type = resource_block.get("type", "")
        resource_name = resource_block.get("name", "")
        provider = resource_block.get("provider", "")
        
        # Only check AWS resources
        if not provider.endswith("aws"):
            continue
        
        for instance in resource_block.get("instances", []):
            attrs = instance.get("attributes", {})
            
            # Map Terraform resource types to AWS Config types
            aws_resource_type = map_tf_to_config_type(resource_type)
            if not aws_resource_type:
                continue
            
            resource_id = get_resource_id(resource_type, attrs)
            if not resource_id:
                continue
            
            resources.append({
                "tf_type": resource_type,
                "tf_name": resource_name,
                "aws_type": aws_resource_type,
                "resource_id": resource_id,
                "tf_attributes": attrs
            })
    
    return resources


def map_tf_to_config_type(tf_type: str) -> str | None:
    """Map Terraform resource type to AWS Config resource type."""
    mapping = {
        "aws_s3_bucket": "AWS::S3::Bucket",
        "aws_security_group": "AWS::EC2::SecurityGroup",
        "aws_instance": "AWS::EC2::Instance",
        "aws_lambda_function": "AWS::Lambda::Function",
        "aws_dynamodb_table": "AWS::DynamoDB::Table",
        "aws_iam_role": "AWS::IAM::Role",
        "aws_sns_topic": "AWS::SNS::Topic",
        "aws_sqs_queue": "AWS::SQS::Queue",
    }
    return mapping.get(tf_type)


def get_resource_id(tf_type: str, attrs: dict) -> str | None:
    """Extract resource ID from Terraform attributes."""
    id_keys = {
        "aws_s3_bucket": "bucket",
        "aws_security_group": "id",
        "aws_instance": "id",
        "aws_lambda_function": "function_name",
        "aws_dynamodb_table": "name",
        "aws_iam_role": "name",
        "aws_sns_topic": "arn",
        "aws_sqs_queue": "url",
    }
    key = id_keys.get(tf_type, "id")
    return attrs.get(key, attrs.get("id"))


def check_resource_drift(resource: dict) -> dict | None:
    """
    Check if a resource has drifted from Terraform state.
    
    Returns drift info if drifted, None otherwise.
    """
    resource_type = resource["aws_type"]
    resource_id = resource["resource_id"]
    tf_attrs = resource["tf_attributes"]
    
    try:
        # Query AWS Config for current resource configuration
        response = config_client.get_resource_config_history(
            resourceType=resource_type,
            resourceId=resource_id,
            limit=1,
            chronologicalOrder="Reverse"
        )
        
        items = response.get("configurationItems", [])
        if not items:
            logger.warning(f"Resource not found in Config: {resource_type}/{resource_id}")
            return None
        
        current_config = items[0]
        config_data = json.loads(current_config.get("configuration", "{}"))
        
        # Compare key attributes based on resource type
        drift_details = compare_attributes(resource_type, tf_attrs, config_data)
        
        if drift_details:
            return {
                "resource_type": resource_type,
                "resource_id": resource_id,
                "tf_name": resource["tf_name"],
                "drift_details": drift_details,
                "detected_at": datetime.now(timezone.utc).isoformat()
            }
        
        return None
        
    except ClientError as e:
        if "ResourceNotDiscoveredException" in str(e):
            logger.warning(f"Resource not discovered by Config: {resource_type}/{resource_id}")
        else:
            logger.error(f"Error checking drift for {resource_id}: {e}")
        return None


def compare_attributes(resource_type: str, tf_attrs: dict, config_data: dict) -> list[dict]:
    """Compare Terraform attributes with AWS Config data."""
    diffs = []
    
    # Define key attributes to check per resource type
    check_keys = {
        "AWS::S3::Bucket": [
            ("versioning.0.enabled", "VersioningConfiguration.Status", 
             lambda tf, aws: (tf == True and aws == "Enabled") or (tf == False and aws != "Enabled")),
        ],
        "AWS::EC2::SecurityGroup": [
            ("description", "description", lambda tf, aws: tf == aws),
        ],
        "AWS::Lambda::Function": [
            ("runtime", "runtime", lambda tf, aws: tf == aws),
            ("memory_size", "memorySize", lambda tf, aws: tf == aws),
            ("timeout", "timeout", lambda tf, aws: tf == aws),
        ],
        "AWS::DynamoDB::Table": [
            ("billing_mode", "billingModeSummary.billingMode", 
             lambda tf, aws: tf == aws or (tf == "PAY_PER_REQUEST" and aws == "PAY_PER_REQUEST")),
        ],
    }
    
    keys_to_check = check_keys.get(resource_type, [])
    
    for tf_key, aws_key, compare_fn in keys_to_check:
        tf_value = get_nested_value(tf_attrs, tf_key)
        aws_value = get_nested_value(config_data, aws_key)
        
        if tf_value is not None and aws_value is not None:
            if not compare_fn(tf_value, aws_value):
                diffs.append({
                    "attribute": tf_key,
                    "terraform_value": str(tf_value),
                    "actual_value": str(aws_value)
                })
    
    return diffs


def get_nested_value(data: dict, key_path: str) -> Any:
    """Get nested value from dict using dot notation."""
    keys = key_path.split(".")
    value = data
    
    for key in keys:
        if isinstance(value, dict):
            value = value.get(key)
        elif isinstance(value, list) and key.isdigit():
            idx = int(key)
            value = value[idx] if idx < len(value) else None
        else:
            return None
        
        if value is None:
            return None
    
    return value


def send_drift_alert(drift_results: list[dict]) -> None:
    """Send drift alert via notification Lambda."""
    if not NOTIFICATION_LAMBDA:
        logger.warning("Notification Lambda not configured")
        return
    
    # Build alert message
    message = "🔄 **Terraform Drift Detected**\n\n"
    message += f"Detected {len(drift_results)} resources with configuration drift:\n\n"
    
    for drift in drift_results[:10]:  # Limit to first 10
        message += f"• **{drift['resource_type']}**: `{drift['resource_id']}`\n"
        for detail in drift.get("drift_details", []):
            message += f"  - {detail['attribute']}: TF=`{detail['terraform_value']}` vs Actual=`{detail['actual_value']}`\n"
    
    if len(drift_results) > 10:
        message += f"\n...and {len(drift_results) - 10} more.\n"
    
    message += "\n⚠️ Run `terraform plan` to see full drift and `terraform apply` to reconcile."
    
    payload = {
        "action": "notify",
        "compliance_data": {
            "rule_name": "terraform-drift-detection",
            "resource_id": "multiple-resources",
            "resource_type": "Terraform::State",
            "account_id": os.environ.get("AWS_ACCOUNT_ID", "governance"),
            "region": os.environ.get("AWS_REGION", "us-east-1"),
            "severity": "HIGH",
            "annotation": message
        }
    }
    
    try:
        lambda_client.invoke(
            FunctionName=NOTIFICATION_LAMBDA,
            InvocationType="Event",
            Payload=json.dumps(payload)
        )
        logger.info("Drift alert sent via notification Lambda")
    except ClientError as e:
        logger.error(f"Failed to send drift alert: {e}")
