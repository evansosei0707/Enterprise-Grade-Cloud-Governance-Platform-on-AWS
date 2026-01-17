"""
Policy Engine Lambda Handler
============================
Processes AWS Config compliance events and routes them based on severity.

Responsibilities:
1. Parse Config compliance change events
2. Identify account, region, resource, and violated rule
3. Check for approved exceptions (whitelist)
4. Classify severity (LOW, MEDIUM, HIGH)
5. Persist to DynamoDB
6. Route to remediation or notification

Severity Classification:
- LOW: Auto-remediate (missing tags, public S3)
- MEDIUM: Notify (security group issues)
- HIGH: Log only (requires manual review)

Exception Management:
- Resources with approved exceptions are skipped
- Exceptions must have status="approved" and not be expired

This handler is IDEMPOTENT - safe to retry on the same event.
"""

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any, Optional

import boto3
from botocore.exceptions import ClientError

# Configure logging
log_level = os.environ.get("LOG_LEVEL", "INFO")
logger = logging.getLogger()
logger.setLevel(getattr(logging, log_level))

# AWS clients
dynamodb = boto3.resource("dynamodb")
lambda_client = boto3.client("lambda")

# Environment variables
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "cloud-governance-compliance-history")
EXCEPTIONS_TABLE = os.environ.get("EXCEPTIONS_TABLE", "")
REMEDIATION_LAMBDA = os.environ.get("REMEDIATION_LAMBDA", "")
NOTIFICATION_LAMBDA = os.environ.get("NOTIFICATION_LAMBDA", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "governance")

# Severity classification mapping
# LOW = Auto-remediate, MEDIUM = Notify, HIGH = Log only
RULE_SEVERITY = {
    # LOW - Auto-remediate (non-prod only for SG, all envs for S3/tags)
    "required-tags": "LOW",
    "s3-bucket-public-read-prohibited": "LOW",
    "s3-bucket-level-public-access-prohibited": "LOW",  # Enforce BPA always ON
    "restricted-ssh": "LOW",      # Auto-remediate open SSH (prod safety in remediation engine)
    "restricted-rdp": "LOW",      # Auto-remediate open RDP (prod safety in remediation engine)
    
    # MEDIUM - Notify
    "s3-bucket-public-write-prohibited": "MEDIUM",
    "restricted-common-ports": "MEDIUM",
    
    # HIGH - Log only (manual review required)
    "ec2-instance-managed-by-ssm": "HIGH",
    "iam-user-mfa-enabled": "HIGH",
    "root-account-mfa-enabled": "HIGH",
}


def lambda_handler(event: dict, context: Any) -> dict:
    """
    Main entry point for processing Config compliance events.
    
    Args:
        event: EventBridge event containing Config compliance details
        context: Lambda context
    
    Returns:
        dict with statusCode and processing result
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # Parse the compliance event
        compliance_data = parse_compliance_event(event)
        if not compliance_data:
            logger.warning("Event is not a valid compliance change notification")
            return {"statusCode": 200, "body": "Skipped - not a compliance event"}
        
        # Only process NON_COMPLIANT resources
        if compliance_data["compliance_type"] != "NON_COMPLIANT":
            logger.info(f"Resource {compliance_data['resource_id']} is COMPLIANT, skipping")
            return {"statusCode": 200, "body": "Skipped - resource is compliant"}
        
        # Check for approved exception (whitelist)
        exception = check_exception(
            account_id=compliance_data["account_id"],
            resource_id=compliance_data["resource_id"],
            rule_name=compliance_data["rule_name"]
        )
        
        if exception:
            logger.info(
                f"Resource {compliance_data['resource_id']} has approved exception for "
                f"rule {compliance_data['rule_name']}. Reason: {exception.get('reason', 'N/A')}. "
                f"Approved by: {exception.get('approved_by', 'N/A')}. Skipping."
            )
            # Still persist the record but mark as excepted
            compliance_data["exception_applied"] = True
            compliance_data["exception_reason"] = exception.get("reason", "")
            persist_compliance_record(compliance_data)
            
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "message": "Skipped - approved exception exists",
                    "exception_reason": exception.get("reason", ""),
                    "approved_by": exception.get("approved_by", "")
                })
            }
        
        # Classify severity
        severity = classify_severity(compliance_data["rule_name"])
        compliance_data["severity"] = severity
        
        logger.info(
            f"Processing violation: {compliance_data['rule_name']} "
            f"on {compliance_data['resource_id']} "
            f"in account {compliance_data['account_id']} "
            f"(severity: {severity})"
        )
        
        # Persist to DynamoDB (idempotent)
        persist_compliance_record(compliance_data)
        
        # Route based on severity
        if severity == "LOW":
            invoke_remediation(compliance_data)
        elif severity == "MEDIUM":
            invoke_notification(compliance_data)
        else:  # HIGH
            logger.info(f"HIGH severity - logging only, manual review required")
        
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Processed successfully",
                "severity": severity,
                "action": get_action_for_severity(severity)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}", exc_info=True)
        raise


def check_exception(account_id: str, resource_id: str, rule_name: str) -> Optional[dict]:
    """
    Check if an approved exception exists for this resource and rule.
    
    Returns:
        Exception record dict if approved and not expired, None otherwise
    """
    if not EXCEPTIONS_TABLE:
        logger.debug("Exceptions table not configured, skipping check")
        return None
    
    try:
        table = dynamodb.Table(EXCEPTIONS_TABLE)
        pk = f"EXCEPTION#{account_id}#{resource_id}"
        sk = f"RULE#{rule_name}"
        
        response = table.get_item(
            Key={"pk": pk, "sk": sk}
        )
        
        item = response.get("Item")
        if not item:
            return None
        
        # Check if exception is approved
        if item.get("status") != "approved":
            logger.debug(f"Exception found but status is {item.get('status')}, not approved")
            return None
        
        # Check if exception is expired (TTL is handled by DynamoDB, but double-check)
        expires_at = item.get("expires_at")
        if expires_at:
            # expires_at is stored as epoch timestamp
            if int(expires_at) < int(time.time()):
                logger.debug(f"Exception found but expired at {expires_at}")
                return None
        
        return item
        
    except ClientError as e:
        logger.error(f"Error checking exception: {e}")
        return None


def parse_compliance_event(event: dict) -> dict | None:
    """
    Extract relevant fields from Config compliance event.
    
    Returns:
        Parsed compliance data or None if invalid event
    """
    try:
        detail = event.get("detail", {})
        
        # Validate this is a compliance change notification
        if detail.get("messageType") != "ComplianceChangeNotification":
            return None
        
        return {
            "account_id": event.get("account", ""),
            "region": event.get("region", ""),
            "resource_id": detail.get("resourceId", ""),
            "resource_type": detail.get("resourceType", ""),
            "rule_name": detail.get("configRuleName", ""),
            "compliance_type": detail.get("newEvaluationResult", {}).get("complianceType", ""),
            "annotation": detail.get("newEvaluationResult", {}).get("annotation", ""),
            "timestamp": event.get("time", datetime.now(timezone.utc).isoformat()),
            "event_id": event.get("id", ""),
        }
    except (KeyError, TypeError) as e:
        logger.error(f"Failed to parse compliance event: {e}")
        return None


def classify_severity(rule_name: str) -> str:
    """
    Classify rule violation severity.
    
    Args:
        rule_name: Name of the violated Config rule
    
    Returns:
        Severity level: LOW, MEDIUM, or HIGH
    """
    return RULE_SEVERITY.get(rule_name, "MEDIUM")


def persist_compliance_record(data: dict) -> None:
    """
    Store compliance record in DynamoDB.
    
    Uses conditional write for idempotency based on event_id.
    """
    table = dynamodb.Table(DYNAMODB_TABLE)
    
    # Create partition and sort keys for efficient querying
    pk = f"ACCOUNT#{data['account_id']}#RESOURCE#{data['resource_id']}"
    sk = f"TIMESTAMP#{data['timestamp']}"
    
    # Calculate TTL (2 years from now)
    ttl = int(time.time()) + (365 * 2 * 24 * 60 * 60)
    
    item = {
        "pk": pk,
        "sk": sk,
        "account_id": data["account_id"],
        "region": data["region"],
        "resource_id": data["resource_id"],
        "resource_type": data["resource_type"],
        "rule_name": data["rule_name"],
        "compliance_type": data["compliance_type"],
        "severity": data.get("severity", "UNKNOWN"),
        "annotation": data.get("annotation", ""),
        "event_id": data["event_id"],
        "processed_at": datetime.now(timezone.utc).isoformat(),
        "ttl": ttl,
    }
    
    # Add exception info if present
    if data.get("exception_applied"):
        item["exception_applied"] = True
        item["exception_reason"] = data.get("exception_reason", "")
    
    try:
        # Use condition to prevent duplicate processing
        table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(pk) OR attribute_not_exists(sk)"
        )
        logger.info(f"Persisted compliance record: {pk}")
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            logger.info(f"Record already exists (idempotent): {pk}")
        else:
            raise


def invoke_remediation(data: dict) -> None:
    """
    Invoke the remediation Lambda for LOW severity violations.
    """
    if not REMEDIATION_LAMBDA:
        logger.warning("Remediation Lambda not configured")
        return
    
    payload = {
        "action": "remediate",
        "compliance_data": data,
        "invoked_at": datetime.now(timezone.utc).isoformat(),
    }
    
    try:
        response = lambda_client.invoke(
            FunctionName=REMEDIATION_LAMBDA,
            InvocationType="Event",  # Async invocation
            Payload=json.dumps(payload),
        )
        logger.info(f"Invoked remediation Lambda: {response['StatusCode']}")
    except ClientError as e:
        logger.error(f"Failed to invoke remediation Lambda: {e}")
        raise


def invoke_notification(data: dict) -> None:
    """
    Invoke the notification Lambda for MEDIUM severity violations.
    """
    if not NOTIFICATION_LAMBDA:
        logger.warning("Notification Lambda not configured")
        return
    
    payload = {
        "action": "notify",
        "compliance_data": data,
        "invoked_at": datetime.now(timezone.utc).isoformat(),
    }
    
    try:
        response = lambda_client.invoke(
            FunctionName=NOTIFICATION_LAMBDA,
            InvocationType="Event",  # Async invocation
            Payload=json.dumps(payload),
        )
        logger.info(f"Invoked notification Lambda: {response['StatusCode']}")
    except ClientError as e:
        logger.error(f"Failed to invoke notification Lambda: {e}")
        raise


def get_action_for_severity(severity: str) -> str:
    """Map severity to action taken."""
    return {
        "LOW": "auto_remediate",
        "MEDIUM": "notify",
        "HIGH": "log_only",
    }.get(severity, "unknown")
