"""
Notification Lambda Handler
===========================
Formats compliance events and publishes to SNS.
"""

import json
import logging
import os
import boto3
from typing import Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
SNS_CLIENT = boto3.client("sns")

def lambda_handler(event: dict, context: Any) -> dict:
    logger.info(f"Received notification request: {json.dumps(event)}")
    
    compliance_data = event.get("compliance_data", {})
    account_id = compliance_data.get("account_id")
    rule_name = compliance_data.get("rule_name")
    severity = compliance_data.get("severity")
    resource_id = compliance_data.get("resource_id")
    
    subject = f"[{severity}] Config Rule Violation: {rule_name}"
    message = (
        f"AWS Config Rule Violation Detected\n"
        f"----------------------------------\n"
        f"Severity: {severity}\n"
        f"Rule: {rule_name}\n"
        f"Account: {account_id}\n"
        f"Resource: {resource_id}\n"
        f"Region: {compliance_data.get('region')}\n\n"
        f"Action Required: Check cloud governance dashboard."
    )
    
    try:
        SNS_CLIENT.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject[:100],  # Max 100 chars
            Message=message
        )
        logger.info("Notification sent successfully")
        return {"statusCode": 200, "body": "Notification sent"}
    except Exception as e:
        logger.error(f"Failed to send notification: {e}")
        raise
