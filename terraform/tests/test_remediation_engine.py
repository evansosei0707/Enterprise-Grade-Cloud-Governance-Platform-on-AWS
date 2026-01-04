
import json
import os
import sys
import pytest
from unittest.mock import MagicMock, patch

# Add lambda src to path
sys.path.append(os.path.join(os.path.dirname(__file__), "../modules/lambdas/remediation-engine/src"))

from handler import lambda_handler

@pytest.fixture
def mock_env():
    with patch.dict(os.environ, {
        "REMEDIATION_ROLE_NAME": "TestRole",
        "EXTERNAL_ID": "TestID"
    }):
        yield

@pytest.fixture
def mock_sts():
    with patch("handler.STS_CLIENT") as mock_sts:
        mock_sts.assume_role.return_value = {
            "Credentials": {
                "AccessKeyId": "ASIA...",
                "SecretAccessKey": "secret",
                "SessionToken": "token"
            }
        }
        yield mock_sts

@pytest.fixture
def mock_s3_session():
    with patch("handler.boto3.Session") as MockSession:
        mock_s3 = MagicMock()
        MockSession.return_value.client.return_value = mock_s3
        yield mock_s3

def test_remediate_s3_public_read(mock_env, mock_sts, mock_s3_session):
    event = {
        "action": "remediate",
        "compliance_data": {
            "account_id": "123456789012",
            "region": "us-east-1",
            "resource_id": "my-bucket",
            "rule_name": "s3-bucket-public-read-prohibited",
            "resource_type": "AWS::S3::Bucket"
        }
    }

    response = lambda_handler(event, None)
    
    assert response["statusCode"] == 200
    
    # Verify Assume Role
    mock_sts.assume_role.assert_called_with(
        RoleArn="arn:aws:iam::123456789012:role/TestRole",
        RoleSessionName="GovernanceRemediationEngine",
        ExternalId="TestID"
    )
    
    # Verify S3 PutPublicAccessBlock
    mock_s3_session.put_public_access_block.assert_called_once()
    call_args = mock_s3_session.put_public_access_block.call_args
    assert call_args.kwargs["Bucket"] == "my-bucket"
    assert call_args.kwargs["PublicAccessBlockConfiguration"]["BlockPublicAcls"] is True

def test_unknown_action(mock_env):
    event = {"action": "scale_down"}
    response = lambda_handler(event, None)
    assert response["statusCode"] == 400
    assert "Unknown action" in response["body"]
