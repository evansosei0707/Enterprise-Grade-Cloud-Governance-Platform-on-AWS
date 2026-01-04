
import json
import os
import sys
import pytest
from unittest.mock import MagicMock, patch

# Add lambda src to path
sys.path.append(os.path.join(os.path.dirname(__file__), "../modules/lambdas/policy-engine/src"))

from handler import lambda_handler, classify_severity

@pytest.fixture
def mock_env():
    with patch.dict(os.environ, {
        "DYNAMODB_TABLE": "test-table",
        "REMEDIATION_LAMBDA": "remediation-func",
        "NOTIFICATION_LAMBDA": "notification-func",
        "ENVIRONMENT": "test"
    }):
        yield

@pytest.fixture
def mock_boto():
    with patch("handler.boto3") as mock_boto:
        mock_dynamo = MagicMock()
        mock_lambda = MagicMock()
        mock_boto.resource.return_value = mock_dynamo
        mock_boto.client.return_value = mock_lambda
        yield mock_boto

def test_classify_severity():
    assert classify_severity("required-tags") == "LOW"
    assert classify_severity("restricted-ssh") == "MEDIUM"
    assert classify_severity("root-account-mfa-enabled") == "HIGH"
    assert classify_severity("unknown-rule") == "MEDIUM"  # Default

def test_lambda_handler_compliance_event(mock_env, mock_boto):
    event = {
        "detail": {
            "messageType": "ComplianceChangeNotification",
            "resourceId": "i-12345",
            "resourceType": "AWS::EC2::Instance",
            "configRuleName": "required-tags",
            "newEvaluationResult": {
                "complianceType": "NON_COMPLIANT",
                "annotation": "Missing tags"
            }
        },
        "account": "123456789012",
        "region": "us-east-1",
        "time": "2024-01-01T00:00:00Z",
        "id": "event-123"
    }

    response = lambda_handler(event, None)
    
    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["severity"] == "LOW"
    assert body["action"] == "auto_remediate"

    # Verify DynamoDB persistence
    mock_boto.resource.return_value.Table.return_value.put_item.assert_called_once()
    
    # Verify Remediation Lambda invocation
    mock_boto.client.return_value.invoke.assert_called_once()
    call_args = mock_boto.client.return_value.invoke.call_args
    assert call_args.kwargs["FunctionName"] == "remediation-func"

def test_lambda_handler_compliant_resource(mock_env, mock_boto):
    event = {
        "detail": {
            "messageType": "ComplianceChangeNotification",
            "configRuleName": "required-tags",
            "newEvaluationResult": {
                "complianceType": "COMPLIANT"
            }
        }
    }

    response = lambda_handler(event, None)
    assert response["statusCode"] == 200
    assert "Skipped" in response["body"]
    mock_boto.client.return_value.invoke.assert_not_called()
