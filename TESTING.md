# org-wide-governance-platform

## Testing & Verification Guide

This guide details how to validate the organization-wide governance platform by deploying non-compliant resources and monitoring their detection, aggregation, and auto-remediation.

---

### 1. Test Architecture

We will deploy a dedicated **Testing Suite** (`terraform/testing`) that intentionally provisions non-compliant resources into the Member Accounts (Dev, Staging, Prod).

#### Target Resources
1.  **S3 Bucket**: Missing tags, Public Read/Write ACLs enabled.
2.  **Security Group**: Open SSH (0.0.0.0/0 on port 22), Open RDP (port 3389).
3.  **EC2 Instance**: Missing tags, stopped state (mock).
4.  **RDS Instance**: Missing tags.

---

### 2. Deployment Instructions

#### Prerequisites
*   Assumes you have valid SSO profiles: `governance`, `dev`, `staging`, `prod`.
*   You must be in the `terraform/testing` directory.

#### Deploying Non-Compliant Resources (Dev)
```bash
# 1. Switch to testing directory
cd terraform/testing

# 2. Select the workspace (or just use variables) - We will use variables to target Dev
terraform init
terraform apply -var="target_account=dev"
```
*Note: This will deploy resources to the Dev account using the `dev` profile.*

#### Deploying to Staging & Prod
Repeat the apply with the target argument:
```bash
terraform apply -var="target_account=staging"
terraform apply -var="target_account=prod"
```

---

### 3. Verification Steps

#### A. AWS Config Console (Member Accounts)
1.  Login to **Dev Account**.
2.  Go to **AWS Config** -> **Rules**.
3.  Filter by **Non-compliant**.
4.  Verify that `s3-bucket-public-read-prohibited`, `restricted-ssh`, and `required-tags` rules are flagging the new resources.

#### B. Aggregation (Governance Account)
1.  Login to **Governance Account**.
2.  Go to **AWS Config** -> **Aggregators**.
3.  Select the Org Aggregator.
4.  Verify you can see the non-compliant resources from Dev, Staging, and Prod listed here.

#### C. Auto-Remediation (Event Pipeline)
1.  **Check DynamoDB**: Go to Governance Account -> DynamoDB -> `cloud-governance-compliance-history`.
    *   Verify a new item exists for the non-compliant resource event.
2.  **Check Lambda Logs**: Go to CloudWatch Logs -> `/aws/lambda/cloud-governance-governance-policy-engine`.
    *   Look for "Severity classified as HIGH" or "Invoking remediation".
3.  **Verify Action**:
    *   **S3**: Check if the public ACL was removed from the bucket in Dev.
    *   **SG**: Check if the ingress rule for port 22 was removed.

---

### 4. Cleanup
After testing, destroy the non-compliant resources to clean up the environment.

```bash
terraform destroy -var="target_account=dev"
terraform destroy -var="target_account=staging"
terraform destroy -var="target_account=prod"
```
