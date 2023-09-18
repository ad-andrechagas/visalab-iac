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

resource "random_pet" "this" {
  length = 2
}


module "bucket" {
  source = "../../../tf-modules/dev/s3/"
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
