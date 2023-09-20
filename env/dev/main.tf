# Visalab IAC Development Environment #
#######################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket  = "lab-terraform-state-bucket"
    key     = "dev/terraform.tfstate"
    region  = "us-east-1"
    encrypt = "true"
  }
}

# =================================================================
# This is optional as it is for giving a randomic name in cloud.
resource "random_pet" "this" {
  length = 2
}
# =================================================================

module "visa-bucket" {
  source = "git@github.com:ad-andrechagas/tf-module-s3.git"
  name   = "visalab-${random_pet.this.id}"
  tags = {
    Name        = "VisaLab Bucket"
    Environment = "DEV"
    Managedby   = "VisaLab Team"
  }

  versioning = {
    enabled = true
  }
}
# Under construction
module "visa-rds" {
  source                 = "git@github.com:ad-andrechagas/tf-module-rds.git"
  db_instance_identifier = ""
  db_name                = "demodb"
  # Add more RDS configuration options as needed
}
