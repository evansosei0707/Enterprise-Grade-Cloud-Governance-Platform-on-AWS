#!/bin/bash

# =============================================================================
# AWS Governance Platform Health Check Script
# =============================================================================
# This script performs a comprehensive health check of the governance platform
# across all accounts (dev, staging, prod, governance)
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print section headers
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# =============================================================================
# 1. AWS Config Recorder Status
# =============================================================================
print_header "1. AWS Config Recorder Status"

for profile in Dev Staging Prod governance; do
    echo -e "${YELLOW}Checking $profile account...${NC}"
    
    status=$(aws configservice describe-configuration-recorder-status \
        --profile $profile \
        --query 'ConfigurationRecordersStatus[0].recording' \
        --output text 2>/dev/null || echo "ERROR")
    
    if [ "$status" == "True" ]; then
        print_success "$profile: Config recorder is RECORDING"
    elif [ "$status" == "ERROR" ]; then
        print_error "$profile: Failed to check Config recorder status"
    else
        print_error "$profile: Config recorder is NOT recording"
    fi
done

# =============================================================================
# 2. Config Rules Status
# =============================================================================
print_header "2. Config Rules Status (Member Accounts)"

for profile in Dev Staging Prod; do
    echo -e "${YELLOW}Checking $profile account...${NC}"
    
    rule_count=$(aws configservice describe-config-rules \
        --profile $profile \
        --query 'length(ConfigRules)' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$rule_count" -gt 0 ]; then
        print_success "$profile: $rule_count Config rules active"
        
        # List the rules
        aws configservice describe-config-rules \
            --profile $profile \
            --query 'ConfigRules[].ConfigRuleName' \
            --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /'
    else
        print_error "$profile: No Config rules found"
    fi
    echo ""
done

# =============================================================================
# 3. Compliance Summary
# =============================================================================
print_header "3. Compliance Summary (Member Accounts)"

for profile in Dev Staging Prod; do
    echo -e "${YELLOW}Checking $profile account...${NC}"
    
    summary=$(aws configservice get-compliance-summary-by-config-rule \
        --profile $profile 2>/dev/null || echo "ERROR")
    
    if [ "$summary" != "ERROR" ]; then
        compliant=$(echo "$summary" | grep -oP '"NumberOfCompliantRules":\s*\K\d+' || echo "0")
        non_compliant=$(echo "$summary" | grep -oP '"NumberOfNonCompliantRules":\s*\K\d+' || echo "0")
        
        echo "  Compliant Rules: $compliant"
        echo "  Non-Compliant Rules: $non_compliant"
        
        if [ "$non_compliant" -gt 0 ]; then
            print_warning "$profile has $non_compliant non-compliant rules"
        else
            print_success "$profile: All rules compliant"
        fi
    else
        print_error "$profile: Failed to get compliance summary"
    fi
    echo ""
done

# =============================================================================
# 4. Config Aggregator Status
# =============================================================================
print_header "4. Config Aggregator (Governance Account)"

aggregator_name=$(aws configservice describe-configuration-aggregators \
    --profile governance \
    --query 'ConfigurationAggregators[0].ConfigurationAggregatorName' \
    --output text 2>/dev/null || echo "ERROR")

if [ "$aggregator_name" != "ERROR" ] && [ "$aggregator_name" != "None" ]; then
    print_success "Aggregator found: $aggregator_name"
    
    # Get account count
    account_count=$(aws configservice describe-configuration-aggregators \
        --profile governance \
        --query 'ConfigurationAggregators[0].AccountAggregationSources[0].AllAwsRegions' \
        --output text 2>/dev/null || echo "0")
    
    echo "  Aggregating from: Organization-wide"
else
    print_error "Config aggregator not found"
fi

# =============================================================================
# 5. Lambda Functions Status
# =============================================================================
print_header "5. Lambda Functions (Governance Account)"

expected_lambdas=("policy-engine" "remediation-engine" "notification")

for lambda_suffix in "${expected_lambdas[@]}"; do
    lambda_name="cloud-governance-governance-$lambda_suffix"
    
    status=$(aws lambda get-function \
        --function-name "$lambda_name" \
        --profile governance \
        --query 'Configuration.State' \
        --output text 2>/dev/null || echo "ERROR")
    
    if [ "$status" == "Active" ]; then
        print_success "$lambda_name: Active"
        
        # Get last invocation time
        last_invoked=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/Lambda \
            --metric-name Invocations \
            --dimensions Name=FunctionName,Value=$lambda_name \
            --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
            --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
            --period 3600 \
            --statistics Sum \
            --profile governance \
            --query 'Datapoints[0].Sum' \
            --output text 2>/dev/null || echo "0")
        
        echo "  Invocations (last hour): $last_invoked"
    elif [ "$status" == "ERROR" ]; then
        print_error "$lambda_name: Not found"
    else
        print_warning "$lambda_name: Status is $status"
    fi
done

# =============================================================================
# 6. EventBridge Rule Status
# =============================================================================
print_header "6. EventBridge Rule (Governance Account)"

rule_name="cloud-governance-config-compliance-change"

rule_state=$(aws events describe-rule \
    --name "$rule_name" \
    --profile governance \
    --query 'State' \
    --output text 2>/dev/null || echo "ERROR")

if [ "$rule_state" == "ENABLED" ]; then
    print_success "$rule_name: ENABLED"
    
    # Check targets
    target_count=$(aws events list-targets-by-rule \
        --rule "$rule_name" \
        --profile governance \
        --query 'length(Targets)' \
        --output text 2>/dev/null || echo "0")
    
    echo "  Targets configured: $target_count"
elif [ "$rule_state" == "ERROR" ]; then
    print_error "$rule_name: Not found"
else
    print_warning "$rule_name: State is $rule_state"
fi

# =============================================================================
# 7. DynamoDB Table Status
# =============================================================================
print_header "7. DynamoDB Compliance History (Governance Account)"

table_name="cloud-governance-compliance-history"

table_status=$(aws dynamodb describe-table \
    --table-name "$table_name" \
    --profile governance \
    --query 'Table.TableStatus' \
    --output text 2>/dev/null || echo "ERROR")

if [ "$table_status" == "ACTIVE" ]; then
    print_success "$table_name: ACTIVE"
    
    # Get item count
    item_count=$(aws dynamodb describe-table \
        --table-name "$table_name" \
        --profile governance \
        --query 'Table.ItemCount' \
        --output text 2>/dev/null || echo "0")
    
    echo "  Total items: $item_count"
    
    if [ "$item_count" -gt 0 ]; then
        print_success "Compliance events are being recorded"
    else
        print_warning "No compliance events recorded yet"
    fi
elif [ "$table_status" == "ERROR" ]; then
    print_error "$table_name: Not found"
else
    print_warning "$table_name: Status is $table_status"
fi

# =============================================================================
# 8. S3 Audit Bucket Status
# =============================================================================
print_header "8. S3 Audit Bucket (Governance Account)"

bucket_name="cloud-governance-audit-logs"

bucket_exists=$(aws s3 ls --profile governance 2>/dev/null | grep "$bucket_name" || echo "")

if [ -n "$bucket_exists" ]; then
    print_success "$bucket_name: Exists"
    
    # Check versioning
    versioning=$(aws s3api get-bucket-versioning \
        --bucket "$bucket_name" \
        --profile governance \
        --query 'Status' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$versioning" == "Enabled" ]; then
        print_success "Versioning: Enabled"
    else
        print_warning "Versioning: $versioning"
    fi
    
    # Check for Config logs
    log_count=$(aws s3 ls s3://$bucket_name/AWSLogs/ --recursive --profile governance 2>/dev/null | wc -l || echo "0")
    
    if [ "$log_count" -gt 0 ]; then
        print_success "Config logs present: $log_count files"
    else
        print_warning "No Config logs found yet"
    fi
else
    print_error "$bucket_name: Not found"
fi

# =============================================================================
# 9. IAM Remediation Roles
# =============================================================================
print_header "9. IAM Remediation Roles (Member Accounts)"

role_name="CloudGovernanceRemediationRole"

for profile in Dev Staging Prod governance; do
    role_exists=$(aws iam get-role \
        --role-name "$role_name" \
        --profile $profile \
        --query 'Role.RoleName' \
        --output text 2>/dev/null || echo "ERROR")
    
    if [ "$role_exists" == "$role_name" ]; then
        print_success "$profile: $role_name exists"
    else
        print_error "$profile: $role_name not found"
    fi
done

# =============================================================================
# 10. SNS Topic Status
# =============================================================================
print_header "10. SNS Alert Topic (Governance Account)"

topic_name="cloud-governance-alerts"

topic_arn=$(aws sns list-topics \
    --profile governance \
    --query "Topics[?contains(TopicArn, '$topic_name')].TopicArn" \
    --output text 2>/dev/null || echo "ERROR")

if [ "$topic_arn" != "ERROR" ] && [ -n "$topic_arn" ]; then
    print_success "SNS Topic: $topic_arn"
    
    # Check subscriptions
    sub_count=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$topic_arn" \
        --profile governance \
        --query 'length(Subscriptions)' \
        --output text 2>/dev/null || echo "0")
    
    echo "  Subscriptions: $sub_count"
else
    print_error "SNS topic not found"
fi

# =============================================================================
# Summary
# =============================================================================
print_header "Health Check Complete"

echo -e "${GREEN}✓ All checks completed${NC}"
echo ""
echo "Next steps:"
echo "  1. If any components show errors, review the deployment"
echo "  2. Deploy test resources using: cd terraform/testing && terraform apply"
echo "  3. Monitor Lambda logs: aws logs tail /aws/lambda/cloud-governance-governance-policy-engine --follow --profile governance"
echo "  4. Check compliance: aws configservice get-compliance-summary-by-config-rule --profile dev"
echo ""
