# Security Documentation

Enterprise-grade security whitepaper for the Cloud Governance Platform.

---

## Table of Contents

1. [Threat Model](#1-threat-model)
2. [IAM Least Privilege Analysis](#2-iam-least-privilege-analysis)
3. [Encryption Strategy](#3-encryption-strategy)
4. [Cross-Account Security Model](#4-cross-account-security-model)
5. [Compliance Mapping](#5-compliance-mapping)
6. [Incident Response](#6-incident-response)

---

## 1. Threat Model

### Attack Surfaces

| Surface | Risk | Mitigation |
|---------|------|------------|
| **API Gateway** | Unauthorized access | IAM authentication required |
| **Lambda Functions** | Code injection | Input validation, no eval() |
| **DynamoDB Tables** | Data exfiltration | KMS encryption, VPC endpoints |
| **S3 Buckets** | Public exposure | BPA enforced, bucket policies |
| **Cross-Account Roles** | Privilege escalation | External ID validation |
| **Terraform State** | Credential exposure | S3 encryption, state locking |

### Threat Actors

1. **External Attackers**: Mitigated via IAM auth, no public endpoints
2. **Malicious Insiders**: Limited by least-privilege IAM, audit logging
3. **Compromised Accounts**: Isolated via cross-account boundaries

### Attack Vectors

| Vector | Likelihood | Impact | Controls |
|--------|------------|--------|----------|
| API credential theft | Medium | High | IAM rotation, CloudTrail |
| Lambda code tampering | Low | High | Signed deployments, CI/CD |
| Cross-account lateral movement | Low | Critical | External ID, role restrictions |
| DynamoDB injection | Low | Medium | Type validation in code |

---

## 2. IAM Least Privilege Analysis

### Lambda Execution Roles

#### Policy Engine
```
Permissions:
  - dynamodb:PutItem, GetItem, Query, UpdateItem (compliance table)
  - dynamodb:GetItem, Query (exceptions table)
  - lambda:InvokeFunction (remediation + notification)
  
Scope: Specific table ARNs only
```

#### Remediation Engine
```
Permissions:
  - sts:AssumeRole (cross-account remediation roles)
  - lambda:InvokeFunction (notification)
  
Scope: Specific role ARNs with external ID
```

#### Dashboard API
```
Permissions:
  - dynamodb:GetItem, Query, Scan (compliance table - read only)
  - dynamodb:PutItem, UpdateItem, DeleteItem (exceptions table)
  
Scope: Specific table ARNs only
```

#### Drift Detection
```
Permissions:
  - s3:GetObject (state bucket)
  - config:GetResourceConfigHistory
  - lambda:InvokeFunction (notification)
  
Scope: Specific bucket, all Config resources (required)
```

### Cross-Account Remediation Role

```hcl
Allowed Actions:
  - s3:PutBucketPublicAccessBlock
  - ec2:RevokeSecurityGroupIngress
  - ec2:DescribeSecurityGroups
  - tag:TagResources

Trust Policy:
  - Principal: Governance Lambda role ARN
  - Condition: sts:ExternalId = "CloudGovernance-Remediation-2024"
```

---

## 3. Encryption Strategy

### Data at Rest

| Resource | Encryption | Key Management |
|----------|------------|----------------|
| DynamoDB Tables | AES-256 | AWS Managed KMS |
| S3 Audit Bucket | AES-256 | AWS Managed KMS |
| S3 State Bucket | AES-256 | AWS Managed KMS |
| CloudWatch Logs | AES-256 | AWS Managed |
| Lambda Environment | AES-256 | AWS Managed |

### Data in Transit

| Channel | Encryption |
|---------|------------|
| API Gateway → Lambda | TLS 1.2 |
| Lambda → DynamoDB | TLS 1.2 |
| Lambda → S3 | TLS 1.2 |
| Cross-account STS | TLS 1.2 |
| Slack Webhooks | HTTPS |

### Secrets Management

| Secret | Storage | Rotation |
|--------|---------|----------|
| Slack Webhook URL | Terraform vars (sensitive) | Manual |
| External ID | Terraform hardcoded | Manual |
| GitHub Token | CodeStar Connections | AWS-managed |

---

## 4. Cross-Account Security Model

### Trust Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Governance Account (Control Plane)                          │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Remediation Engine Lambda                           │    │
│  │ Role: cloud-governance-governance-remediation-role  │    │
│  └──────────────────────┬─────────────────────────────┘    │
│                         │                                   │
│                         │ sts:AssumeRole                    │
│                         │ + ExternalId validation           │
└─────────────────────────┼───────────────────────────────────┘
                          │
    ┌─────────────────────┼─────────────────────┐
    ▼                     ▼                     ▼
┌─────────┐         ┌─────────┐           ┌─────────┐
│ Dev     │         │ Staging │           │ Prod    │
│ Account │         │ Account │           │ Account │
├─────────┤         ├─────────┤           ├─────────┤
│ Remedia │         │ Remedia │           │ Remedia │
│ tion    │         │ tion    │           │ tion    │
│ Role    │         │ Role    │           │ Role    │
│         │         │         │           │ (NOTIFY │
│ (FULL)  │         │ (FULL)  │           │  ONLY)  │
└─────────┘         └─────────┘           └─────────┘
```

### Security Controls

1. **External ID**: Prevents confused deputy attacks
2. **Role ARN Validation**: Only specific Lambda can assume
3. **Production Safety**: Security group remediation blocked in prod
4. **IP-based Restrictions**: Not implemented (Lambda doesn't have fixed IPs)

---

## 5. Compliance Mapping

### CIS AWS Foundations Benchmark

| Control | Implementation |
|---------|----------------|
| 1.14 - Ensure MFA is enabled for root | Config rule: `root-account-mfa-enabled` |
| 2.1.1 - S3 Block Public Access | Config rule + auto-remediation |
| 4.1 - No Security Groups with 0.0.0.0/0 | Config rules: `restricted-ssh`, `restricted-rdp` |
| 5.1 - Resource tagging | Config rule: `required-tags` |

### SOC 2 Mapping

| Control | Implementation |
|---------|----------------|
| CC6.1 - Logical Access | IAM least privilege |
| CC6.7 - Encryption | KMS encryption at rest |
| CC7.1 - Configuration Management | Terraform IaC |
| CC7.2 - Change Management | CI/CD pipeline with approvals |

### AWS Well-Architected Security Pillar

| Practice | Implementation |
|----------|----------------|
| SEC 1 - Operate workloads securely | Governance platform monitoring |
| SEC 2 - Identity management | IAM roles, no long-term creds |
| SEC 3 - Permissions management | Least privilege analysis |
| SEC 7 - Classification | Compliance severity classification |
| SEC 8 - Protect data at rest | KMS encryption |
| SEC 9 - Protect data in transit | TLS 1.2 everywhere |

---

## 6. Incident Response

### Runbooks

#### Unauthorized API Access Detected

1. Check CloudTrail for source IP and user identity
2. Revoke IAM credentials if compromised
3. Review API Gateway access logs
4. Enable enhanced logging if not already

#### Cross-Account Compromise Suspected

1. Disable remediation role in affected account
2. Review CloudTrail for AssumeRole events
3. Rotate External ID across all accounts
4. Deploy new remediation roles

#### Lambda Function Compromise

1. View function code/configuration history
2. Roll back to previous version
3. Review invocation logs
4. Update function from clean CI/CD source

### Alerting

| Event | Action |
|-------|--------|
| Lambda errors > 5/min | SNS + Slack notification |
| DLQ messages | CloudWatch alarm |
| Config compliance < 80% | Slack notification |
| Drift detected | SNS + Slack notification |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-17 | Governance Team | Initial release |
