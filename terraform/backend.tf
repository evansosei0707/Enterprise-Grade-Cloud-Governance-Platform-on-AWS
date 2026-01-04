# -----------------------------------------------------------------------------
# Terraform Backend Configuration
# -----------------------------------------------------------------------------
# State stored in S3 with DynamoDB locking in the Governance account.
# Ensure this bucket and table exist before running terraform init.
# -----------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket         = "cloud-governance-terraform-state-257016720202"
    key            = "governance/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "cloud-governance-terraform-locks"
    
    # Assume role into governance account for state access
    role_arn = "arn:aws:iam::257016720202:role/TerraformExecutionRole"
  }
}
