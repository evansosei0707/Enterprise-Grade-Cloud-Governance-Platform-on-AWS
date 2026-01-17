terraform {
  backend "s3" {
    bucket         = "cloud-governance-terraform-state-257016720202"
    key            = "governance/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "cloud-governance-terraform-locks"
  }
}
