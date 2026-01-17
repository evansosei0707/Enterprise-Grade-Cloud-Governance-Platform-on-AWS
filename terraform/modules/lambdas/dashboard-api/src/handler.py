"""
Dashboard API Lambda Handler
============================
REST API for compliance data and exception management.

Endpoints:
- GET /compliance/summary - Org-wide compliance summary
- GET /compliance/accounts/{id} - Account-specific compliance
- GET /compliance/rules/{name} - Violations by rule
- GET /exceptions - List all exceptions
- POST /exceptions - Create exception request (pending approval)
- PUT /exceptions/{id}/approve - Approve exception
- PUT /exceptions/{id}/reject - Reject exception
- DELETE /exceptions/{id} - Delete exception
"""

import json
import logging
import os
import time
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

import boto3
from botocore.exceptions import ClientError

# Configure logging
log_level = os.environ.get("LOG_LEVEL", "INFO")
logger = logging.getLogger()
logger.setLevel(getattr(logging, log_level))

# AWS clients
dynamodb = boto3.resource("dynamodb")

# Environment variables
COMPLIANCE_TABLE = os.environ.get("COMPLIANCE_TABLE", "")
EXCEPTIONS_TABLE = os.environ.get("EXCEPTIONS_TABLE", "")


class DecimalEncoder(json.JSONEncoder):
    """Handle Decimal types from DynamoDB."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)


def lambda_handler(event: dict, context: Any) -> dict:
    """
    Main entry point for API Gateway requests.
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    http_method = event.get("httpMethod", "")
    path = event.get("path", "")
    path_params = event.get("pathParameters") or {}
    query_params = event.get("queryStringParameters") or {}
    body = event.get("body", "")
    
    try:
        # Parse JSON body if present
        body_data = json.loads(body) if body else {}
    except json.JSONDecodeError:
        return response(400, {"error": "Invalid JSON body"})
    
    try:
        # Route based on path and method
        if path == "/compliance/summary" and http_method == "GET":
            return get_compliance_summary()
        
        elif path.startswith("/compliance/accounts/") and http_method == "GET":
            account_id = path_params.get("account_id", "")
            return get_account_compliance(account_id)
        
        elif path.startswith("/compliance/rules/") and http_method == "GET":
            rule_name = path_params.get("rule_name", "")
            return get_rule_violations(rule_name)
        
        elif path == "/exceptions" and http_method == "GET":
            status_filter = query_params.get("status", "")
            return list_exceptions(status_filter)
        
        elif path == "/exceptions" and http_method == "POST":
            return create_exception(body_data)
        
        elif path.startswith("/exceptions/") and "/approve" in path and http_method == "PUT":
            exception_id = path_params.get("exception_id", "")
            return approve_exception(exception_id, body_data)
        
        elif path.startswith("/exceptions/") and "/reject" in path and http_method == "PUT":
            exception_id = path_params.get("exception_id", "")
            return reject_exception(exception_id, body_data)
        
        elif path.startswith("/exceptions/") and http_method == "DELETE":
            exception_id = path_params.get("exception_id", "")
            return delete_exception(exception_id)
        
        else:
            return response(404, {"error": f"Not found: {http_method} {path}"})
    
    except Exception as e:
        logger.error(f"Error processing request: {e}", exc_info=True)
        return response(500, {"error": str(e)})


def response(status_code: int, body: dict) -> dict:
    """Build API Gateway response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization"
        },
        "body": json.dumps(body, cls=DecimalEncoder)
    }


# =============================================================================
# Compliance Endpoints
# =============================================================================

def get_compliance_summary() -> dict:
    """Get org-wide compliance summary."""
    if not COMPLIANCE_TABLE:
        return response(500, {"error": "Compliance table not configured"})
    
    table = dynamodb.Table(COMPLIANCE_TABLE)
    
    # Scan with filter for recent records (last 24 hours)
    cutoff = datetime.now(timezone.utc).isoformat()[:10]  # Today's date
    
    try:
        # Get all NON_COMPLIANT records
        non_compliant = table.query(
            IndexName="compliance-index",
            KeyConditionExpression="compliance_type = :ct",
            ExpressionAttributeValues={":ct": "NON_COMPLIANT"},
            Limit=1000
        )
        
        # Aggregate by account and rule
        by_account = {}
        by_rule = {}
        
        for item in non_compliant.get("Items", []):
            account = item.get("account_id", "unknown")
            rule = item.get("rule_name", "unknown")
            
            by_account[account] = by_account.get(account, 0) + 1
            by_rule[rule] = by_rule.get(rule, 0) + 1
        
        return response(200, {
            "total_violations": len(non_compliant.get("Items", [])),
            "by_account": by_account,
            "by_rule": by_rule,
            "generated_at": datetime.now(timezone.utc).isoformat()
        })
        
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})


def get_account_compliance(account_id: str) -> dict:
    """Get compliance data for a specific account."""
    if not COMPLIANCE_TABLE:
        return response(500, {"error": "Compliance table not configured"})
    
    if not account_id:
        return response(400, {"error": "account_id is required"})
    
    table = dynamodb.Table(COMPLIANCE_TABLE)
    
    try:
        # Query by account ID prefix
        result = table.scan(
            FilterExpression="account_id = :aid AND compliance_type = :ct",
            ExpressionAttributeValues={
                ":aid": account_id,
                ":ct": "NON_COMPLIANT"
            },
            Limit=100
        )
        
        return response(200, {
            "account_id": account_id,
            "violations": result.get("Items", []),
            "count": len(result.get("Items", []))
        })
        
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})


def get_rule_violations(rule_name: str) -> dict:
    """Get all violations for a specific rule."""
    if not COMPLIANCE_TABLE:
        return response(500, {"error": "Compliance table not configured"})
    
    if not rule_name:
        return response(400, {"error": "rule_name is required"})
    
    table = dynamodb.Table(COMPLIANCE_TABLE)
    
    try:
        result = table.query(
            IndexName="rule-index",
            KeyConditionExpression="rule_name = :rn",
            FilterExpression="compliance_type = :ct",
            ExpressionAttributeValues={
                ":rn": rule_name,
                ":ct": "NON_COMPLIANT"
            },
            Limit=100
        )
        
        return response(200, {
            "rule_name": rule_name,
            "violations": result.get("Items", []),
            "count": len(result.get("Items", []))
        })
        
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})


# =============================================================================
# Exception Endpoints
# =============================================================================

def list_exceptions(status_filter: str = "") -> dict:
    """List all exceptions, optionally filtered by status."""
    if not EXCEPTIONS_TABLE:
        return response(500, {"error": "Exceptions table not configured"})
    
    table = dynamodb.Table(EXCEPTIONS_TABLE)
    
    try:
        if status_filter:
            result = table.query(
                IndexName="status-index",
                KeyConditionExpression="status = :s",
                ExpressionAttributeValues={":s": status_filter}
            )
        else:
            result = table.scan(Limit=100)
        
        return response(200, {
            "exceptions": result.get("Items", []),
            "count": len(result.get("Items", []))
        })
        
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})


def create_exception(data: dict) -> dict:
    """Create a new exception request (pending approval)."""
    if not EXCEPTIONS_TABLE:
        return response(500, {"error": "Exceptions table not configured"})
    
    required_fields = ["account_id", "resource_id", "rule_name", "reason", "requested_by"]
    missing = [f for f in required_fields if not data.get(f)]
    if missing:
        return response(400, {"error": f"Missing required fields: {missing}"})
    
    table = dynamodb.Table(EXCEPTIONS_TABLE)
    
    pk = f"EXCEPTION#{data['account_id']}#{data['resource_id']}"
    sk = f"RULE#{data['rule_name']}"
    
    # Calculate expires_at if temporary exception
    expires_at = None
    if data.get("duration_days"):
        expires_at = int(time.time()) + (int(data["duration_days"]) * 24 * 60 * 60)
    
    item = {
        "pk": pk,
        "sk": sk,
        "exception_id": str(uuid.uuid4()),
        "account_id": data["account_id"],
        "resource_id": data["resource_id"],
        "rule_name": data["rule_name"],
        "reason": data["reason"],
        "requested_by": data["requested_by"],
        "status": "pending",  # Requires approval
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    
    if expires_at:
        item["expires_at"] = expires_at
        item["duration_days"] = data["duration_days"]
    
    try:
        table.put_item(Item=item)
        return response(201, {
            "message": "Exception request created (pending approval)",
            "exception_id": item["exception_id"],
            "status": "pending"
        })
        
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})


def approve_exception(exception_id: str, data: dict) -> dict:
    """Approve an exception request."""
    if not EXCEPTIONS_TABLE:
        return response(500, {"error": "Exceptions table not configured"})
    
    approved_by = data.get("approved_by", "")
    if not approved_by:
        return response(400, {"error": "approved_by is required"})
    
    return _update_exception_status(exception_id, "approved", approved_by)


def reject_exception(exception_id: str, data: dict) -> dict:
    """Reject an exception request."""
    if not EXCEPTIONS_TABLE:
        return response(500, {"error": "Exceptions table not configured"})
    
    rejected_by = data.get("rejected_by", "")
    rejection_reason = data.get("rejection_reason", "")
    
    return _update_exception_status(exception_id, "rejected", rejected_by, rejection_reason)


def _update_exception_status(exception_id: str, new_status: str, updated_by: str, reason: str = "") -> dict:
    """Update exception status (approve/reject)."""
    table = dynamodb.Table(EXCEPTIONS_TABLE)
    
    # Find the exception by ID (scan required since exception_id is not a key)
    try:
        result = table.scan(
            FilterExpression="exception_id = :eid",
            ExpressionAttributeValues={":eid": exception_id}
        )
        
        items = result.get("Items", [])
        if not items:
            return response(404, {"error": f"Exception not found: {exception_id}"})
        
        item = items[0]
        pk = item["pk"]
        sk = item["sk"]
        
        update_expr = "SET #status = :status, updated_at = :updated_at, updated_by = :updated_by"
        expr_values = {
            ":status": new_status,
            ":updated_at": datetime.now(timezone.utc).isoformat(),
            ":updated_by": updated_by
        }
        
        if new_status == "approved":
            update_expr += ", approved_by = :approved_by, approved_at = :approved_at"
            expr_values[":approved_by"] = updated_by
            expr_values[":approved_at"] = datetime.now(timezone.utc).isoformat()
        elif new_status == "rejected" and reason:
            update_expr += ", rejection_reason = :rejection_reason"
            expr_values[":rejection_reason"] = reason
        
        table.update_item(
            Key={"pk": pk, "sk": sk},
            UpdateExpression=update_expr,
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues=expr_values
        )
        
        return response(200, {
            "message": f"Exception {new_status}",
            "exception_id": exception_id,
            "status": new_status
        })
        
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})


def delete_exception(exception_id: str) -> dict:
    """Delete an exception."""
    if not EXCEPTIONS_TABLE:
        return response(500, {"error": "Exceptions table not configured"})
    
    table = dynamodb.Table(EXCEPTIONS_TABLE)
    
    try:
        # Find and delete
        result = table.scan(
            FilterExpression="exception_id = :eid",
            ExpressionAttributeValues={":eid": exception_id}
        )
        
        items = result.get("Items", [])
        if not items:
            return response(404, {"error": f"Exception not found: {exception_id}"})
        
        item = items[0]
        table.delete_item(Key={"pk": item["pk"], "sk": item["sk"]})
        
        return response(200, {
            "message": "Exception deleted",
            "exception_id": exception_id
        })
        
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})
