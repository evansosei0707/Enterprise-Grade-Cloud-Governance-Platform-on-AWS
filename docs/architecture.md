# Cloud Governance Platform - Architecture

## Overview

This platform provides **organization-wide governance** across a multi-account AWS Organization with:
- Centralized compliance monitoring via AWS Config
- Event-driven policy enforcement
- Automated remediation for security violations
- Multi-channel notifications (SNS + Slack)

---

## Architecture Diagram

```mermaid
graph TB
    subgraph org["AWS Organization"]
        subgraph member["Member Accounts"]
            subgraph dev["Dev Account"]
                DEV_CONFIG["AWS Config<br/>Recorder + Rules"]
                DEV_ROLE["Remediation<br/>IAM Role"]
            end
            subgraph staging["Staging Account"]
                STG_CONFIG["AWS Config<br/>Recorder + Rules"]
                STG_ROLE["Remediation<br/>IAM Role"]
            end
            subgraph prod["Prod Account"]
                PROD_CONFIG["AWS Config<br/>Recorder + Rules"]
                PROD_ROLE["Remediation<br/>IAM Role"]
            end
            subgraph tooling["Tooling Account"]
                TOOL_CONFIG["AWS Config<br/>Recorder + Rules"]
                TOOL_ROLE["Remediation<br/>IAM Role"]
            end
        end
        
        subgraph governance["Governance Account (Delegated Admin)"]
            AGG["Config<br/>Aggregator"]
            EB["EventBridge<br/>Rules"]
            PE["Policy Engine<br/>Lambda"]
            RE["Remediation Engine<br/>Lambda"]
            NL["Notification<br/>Lambda"]
            DDB["DynamoDB<br/>Compliance History"]
            S3["S3 Bucket<br/>Audit Logs"]
            SNS["SNS Topic<br/>Alerts"]
        end
    end
    
    SLACK["Slack<br/>Channel"]
    EMAIL["Email<br/>Subscribers"]
    
    DEV_CONFIG -->|Compliance Events| EB
    STG_CONFIG -->|Compliance Events| EB
    PROD_CONFIG -->|Compliance Events| EB
    TOOL_CONFIG -->|Compliance Events| EB
    
    DEV_CONFIG --> AGG
    STG_CONFIG --> AGG
    PROD_CONFIG --> AGG
    TOOL_CONFIG --> AGG
    
    EB -->|Trigger| PE
    PE -->|Store| DDB
    PE -->|LOW Severity| RE
    PE -->|MEDIUM Severity| NL
    
    RE -->|Assume Role| DEV_ROLE
    RE -->|Assume Role| STG_ROLE
    RE -.->|Blocked in Prod| NL
    
    NL --> SNS
    NL --> SLACK
    SNS --> EMAIL
    
    classDef governance fill:#e1f5fe,stroke:#0288d1
    classDef member fill:#f3e5f5,stroke:#7b1fa2
    classDef external fill:#fff3e0,stroke:#f57c00
    
    class AGG,EB,PE,RE,NL,DDB,S3,SNS governance
    class DEV_CONFIG,STG_CONFIG,PROD_CONFIG,TOOL_CONFIG,DEV_ROLE,STG_ROLE,PROD_ROLE,TOOL_ROLE member
    class SLACK,EMAIL external
```

---

## Event Flow

### 1. Compliance Detection
1. AWS Config detects non-compliant resource in member account
2. Compliance change event published to EventBridge
3. Event forwarded to Governance account's Event Bus

### 2. Policy Engine Processing
1. Policy Engine Lambda receives event
2. Classifies severity: **LOW**, **MEDIUM**, or **HIGH**
3. Stores record in DynamoDB (idempotent)
4. Routes based on severity

### 3. Remediation (LOW Severity)
| Rule | Action |
|------|--------|
| `required-tags` | Add default tags (environment-aware) |
| `s3-bucket-public-read-prohibited` | Enable Public Access Block |
| `restricted-ssh` | Revoke 0.0.0.0/0 on port 22 |
| `restricted-rdp` | Revoke 0.0.0.0/0 on port 3389 |

> **Production Safety**: SG remediation blocked in prod → notifies instead

### 4. Notification (MEDIUM/HIGH Severity)
- SNS → Email to subscribers
- Slack → Color-coded messages

---

## Environment-Aware Tagging

| Account | Environment | CostCenter |
|---------|-------------|------------|
| Dev | `dev` | `DEV-001` |
| Staging | `staging` | `STG-001` |
| Prod | `prod` | `PROD-001` |
| Governance | `governance` | `INFRA-001` |
| Tooling | `tooling` | `CICD-001` |

---

## Security Features

- ✅ Cross-account IAM with External ID
- ✅ Least privilege remediation permissions
- ✅ Production account protection
- ✅ HTTPS-only S3 bucket policy
- ✅ DynamoDB PITR and encryption
- ✅ KMS support for all storage

---

## Module Structure

```
terraform/
├── modules/
│   ├── aws-config/          # Config recorder + rules
│   ├── config-aggregator/   # Org-wide aggregation
│   ├── eventbridge/         # Compliance event routing
│   ├── iam-remediation-role/# Cross-account access
│   ├── audit/               # S3, DynamoDB, CloudWatch
│   └── lambdas/
│       ├── policy-engine/   # Severity classification
│       ├── remediation-engine/  # Auto-fix violations
│       └── notification/    # SNS + Slack alerts
├── environments/
│   ├── governance/          # Control plane deployment
│   ├── dev/                 # Member account config
│   ├── staging/
│   └── prod/
```
