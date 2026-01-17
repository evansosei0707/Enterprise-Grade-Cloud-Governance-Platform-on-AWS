"""
Notification Lambda Handler
===========================
Formats compliance events and publishes to SNS and Slack.

Features:
- SNS email notifications
- Slack webhook integration with color-coded severity
- Formatted messages with account, resource, and rule info
"""

import json
import logging
import os
from typing import Any
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL", "")
ENABLE_SLACK = os.environ.get("ENABLE_SLACK", "false").lower() == "true"

SNS_CLIENT = boto3.client("sns")

# Severity color mapping for Slack
SEVERITY_COLORS = {
    "LOW": "#36a64f",      # Green - auto-remediated
    "MEDIUM": "#ff9800",   # Orange - notification
    "HIGH": "#ff0000",     # Red - requires attention
}

# Severity emoji for Slack
SEVERITY_EMOJI = {
    "LOW": "🟢",
    "MEDIUM": "🟠", 
    "HIGH": "🔴",
}


def lambda_handler(event: dict, context: Any) -> dict:
    """
    Main entry point for notification processing.
    Sends notifications to both SNS and Slack (if configured).
    """
    logger.info(f"Received notification request: {json.dumps(event)}")
    
    compliance_data = event.get("compliance_data", {})
    account_id = compliance_data.get("account_id", "Unknown")
    rule_name = compliance_data.get("rule_name", "Unknown")
    severity = compliance_data.get("severity", "MEDIUM")
    resource_id = compliance_data.get("resource_id", "Unknown")
    region = compliance_data.get("region", "Unknown")
    resource_type = compliance_data.get("resource_type", "Unknown")
    annotation = compliance_data.get("annotation", "")
    
    # Send SNS notification
    sns_result = send_sns_notification(
        severity=severity,
        rule_name=rule_name,
        account_id=account_id,
        resource_id=resource_id,
        region=region,
        resource_type=resource_type,
        annotation=annotation
    )
    
    # Send Slack notification if enabled
    slack_result = None
    if ENABLE_SLACK and SLACK_WEBHOOK_URL:
        slack_result = send_slack_notification(
            severity=severity,
            rule_name=rule_name,
            account_id=account_id,
            resource_id=resource_id,
            region=region,
            resource_type=resource_type,
            annotation=annotation
        )
    
    return {
        "statusCode": 200,
        "body": json.dumps({
            "sns": sns_result,
            "slack": slack_result
        })
    }


def send_sns_notification(
    severity: str,
    rule_name: str,
    account_id: str,
    resource_id: str,
    region: str,
    resource_type: str,
    annotation: str
) -> str:
    """
    Format and send notification via SNS.
    """
    subject = f"[{severity}] Config Rule Violation: {rule_name}"
    message = (
        f"AWS Config Rule Violation Detected\n"
        f"----------------------------------\n"
        f"Severity: {severity}\n"
        f"Rule: {rule_name}\n"
        f"Account: {account_id}\n"
        f"Region: {region}\n"
        f"Resource Type: {resource_type}\n"
        f"Resource: {resource_id}\n"
    )
    
    if annotation:
        message += f"\nDetails: {annotation}\n"
    
    if severity == "LOW":
        message += "\nAction: Auto-remediation was attempted."
    elif severity == "MEDIUM":
        message += "\nAction Required: Review and remediate manually if needed."
    else:
        message += "\nAction Required: Immediate manual review required."
    
    message += "\n\n--\nCloud Governance Platform"
    
    try:
        SNS_CLIENT.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject[:100],  # Max 100 chars for email subject
            Message=message
        )
        logger.info("SNS notification sent successfully")
        return "sent"
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {e}")
        return f"failed: {str(e)}"


def send_slack_notification(
    severity: str,
    rule_name: str,
    account_id: str,
    resource_id: str,
    region: str,
    resource_type: str,
    annotation: str
) -> str:
    """
    Format and send notification to Slack via webhook.
    Uses Slack attachments for rich formatting with colors.
    """
    emoji = SEVERITY_EMOJI.get(severity, "⚪")
    color = SEVERITY_COLORS.get(severity, "#808080")
    
    # Build action text based on severity
    if severity == "LOW":
        action_text = "✅ Auto-remediation was attempted"
    elif severity == "MEDIUM":
        action_text = "⚠️ Manual review recommended"
    else:
        action_text = "🚨 Immediate manual intervention required"
    
    # Slack payload with attachment for rich formatting
    payload = {
        "attachments": [
            {
                "color": color,
                "pretext": f"{emoji} *AWS Config Rule Violation Detected*",
                "title": f"Rule: {rule_name}",
                "fields": [
                    {
                        "title": "Severity",
                        "value": severity,
                        "short": True
                    },
                    {
                        "title": "Account",
                        "value": account_id,
                        "short": True
                    },
                    {
                        "title": "Region",
                        "value": region,
                        "short": True
                    },
                    {
                        "title": "Resource Type",
                        "value": resource_type,
                        "short": True
                    },
                    {
                        "title": "Resource ID",
                        "value": f"`{resource_id}`",
                        "short": False
                    }
                ],
                "footer": "Cloud Governance Platform",
                "footer_icon": "https://a.slack-edge.com/80588/img/services/outgoing-webhook_48.png"
            }
        ]
    }
    
    # Add annotation if present
    if annotation:
        payload["attachments"][0]["fields"].append({
            "title": "Details",
            "value": annotation,
            "short": False
        })
    
    # Add action text
    payload["attachments"][0]["fields"].append({
        "title": "Action",
        "value": action_text,
        "short": False
    })
    
    try:
        request = Request(
            SLACK_WEBHOOK_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        
        with urlopen(request, timeout=10) as response:
            response_body = response.read().decode("utf-8")
            logger.info(f"Slack notification sent successfully: {response_body}")
            return "sent"
            
    except HTTPError as e:
        logger.error(f"Slack HTTP error: {e.code} - {e.read().decode('utf-8')}")
        return f"failed: HTTP {e.code}"
    except URLError as e:
        logger.error(f"Slack URL error: {e.reason}")
        return f"failed: {str(e.reason)}"
    except Exception as e:
        logger.error(f"Slack notification error: {e}")
        return f"failed: {str(e)}"
