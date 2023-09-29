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

locals {
  bucket_name = "vs-bucket-${random_pet.this.id}"
  region      = "us-east-1"
  tags = {
    Owner       = "Advision Consulting LTDA"
    Team        = "VS-Lab"
    Environment = "DEV"
  }
}

locals {
  name    = "vslab"
  region2 = "us-east-2"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

resource "random_pet" "this" {
  length = 1
}

resource "aws_kms_key" "objects" {
  description             = "KMS key is used to encrypt bucket objects"
  deletion_window_in_days = 7
}

resource "aws_iam_role" "this" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

module "s3_bucket" {
  source = "git@github.com:ad-andrechagas/tf-module-s3.git"

  bucket = "vsbucket-dev"
  tags   = local.tags

  force_destroy = true
}

module "rds" {
  source = "git@github.com:ad-andrechagas/tf-module-rds.git"

  identifier                     = "${local.name}-dev"
  instance_use_identifier_prefix = true

  create_db_option_group    = false
  create_db_parameter_group = false

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine               = "postgres"
  engine_version       = "15"
  family               = "postgres15" # DB parameter group
  major_engine_version = "15"         # DB option group
  instance_class       = "db.t4g.micro"

  allocated_storage = 20

  # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
  # "Error creating DB Instance: InvalidParameterValue: MasterUsername
  # user cannot be used as it is a reserved word used by the engine"
  db_name  = "vslabdbdev"
  username = "vslab"
  port     = 5432

  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.security_group.security_group_id]

  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_window           = "03:00-06:00"
  backup_retention_period = 0

  tags = local.tags
}
################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs              = local.azs
  public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 3)]
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 6)]

  create_database_subnet_group = true

  tags = local.tags
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = local.name
  description = "Complete PostgreSQL example security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  tags = local.tags
}


# To be tested ... 
# =======================================
# module "log_bucket" {
#   source = "git@github.com:ad-andrechagas/tf-module-s3.git"

#   bucket        = "logs-${random_pet.this.id}"
#   force_destroy = true

#   control_object_ownership = true

#   attach_elb_log_delivery_policy        = true
#   attach_lb_log_delivery_policy         = true
#   attach_access_log_delivery_policy     = true
#   attach_deny_insecure_transport_policy = true
#   attach_require_latest_tls_policy      = true

#   access_log_delivery_policy_source_accounts = [data.aws_caller_identity.current.account_id]
#   access_log_delivery_policy_source_buckets  = ["arn:aws:s3:::${local.bucket_name}"]
# }

# module "cloudfront_log_bucket" {
#   source = "git@github.com:ad-andrechagas/tf-module-s3.git"

#   bucket                   = "cloudfront-logs-${random_pet.this.id}"
#   control_object_ownership = true
#   object_ownership         = "ObjectWriter"

#   grant = [{
#     type       = "CanonicalUser"
#     permission = "FULL_CONTROL"
#     id         = data.aws_canonical_user_id.current.id
#     }, {
#     type       = "CanonicalUser"
#     permission = "FULL_CONTROL"
#     id         = data.aws_cloudfront_log_delivery_canonical_user_id.cloudfront.id # Ref. https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/AccessLogs.html
#     }
#   ]

#   owner = {
#     id = data.aws_canonical_user_id.current.id
#   }

#   force_destroy = true
# }

# module "s3_bucket-complete" {
#   source = "git@github.com:ad-andrechagas/tf-module-s3.git"

#   bucket = local.bucket_name

#   force_destroy       = true
#   acceleration_status = "Suspended"
#   request_payer       = "BucketOwner"

#   tags = {
#     Owner = "Anton"
#   }

#   # Note: Object Lock configuration can be enabled only on new buckets
#   # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration
#   object_lock_enabled = true
#   object_lock_configuration = {
#     rule = {
#       default_retention = {
#         mode = "GOVERNANCE"
#         days = 1
#       }
#     }
#   }

#   # Bucket policies
#   attach_policy                            = true
#   policy                                   = data.aws_iam_policy_document.bucket_policy.json
#   attach_deny_insecure_transport_policy    = true
#   attach_require_latest_tls_policy         = true
#   attach_deny_incorrect_encryption_headers = true
#   attach_deny_incorrect_kms_key_sse        = true
#   allowed_kms_key_arn                      = aws_kms_key.objects.arn
#   attach_deny_unencrypted_object_uploads   = true

#   # S3 bucket-level Public Access Block configuration (by default now AWS has made this default as true for S3 bucket-level block public access)
#   # block_public_acls       = true
#   # block_public_policy     = true
#   # ignore_public_acls      = true
#   # restrict_public_buckets = true

#   # S3 Bucket Ownership Controls
#   # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls
#   control_object_ownership = true
#   object_ownership         = "BucketOwnerPreferred"

#   expected_bucket_owner = data.aws_caller_identity.current.account_id

#   acl = "private" # "acl" conflicts with "grant" and "owner"

#   logging = {
#     target_bucket = module.log_bucket.s3_bucket_id
#     target_prefix = "log/"
#   }

#   versioning = {
#     status     = true
#     mfa_delete = false
#   }

#   website = {
#     # conflicts with "error_document"
#     #        redirect_all_requests_to = {
#     #          host_name = "https://modules.tf"
#     #        }

#     index_document = "index.html"
#     error_document = "error.html"
#     routing_rules = [{
#       condition = {
#         key_prefix_equals = "docs/"
#       },
#       redirect = {
#         replace_key_prefix_with = "documents/"
#       }
#       }, {
#       condition = {
#         http_error_code_returned_equals = 404
#         key_prefix_equals               = "archive/"
#       },
#       redirect = {
#         host_name          = "archive.myhost.com"
#         http_redirect_code = 301
#         protocol           = "https"
#         replace_key_with   = "not_found.html"
#       }
#     }]
#   }

#   server_side_encryption_configuration = {
#     rule = {
#       apply_server_side_encryption_by_default = {
#         kms_master_key_id = aws_kms_key.objects.arn
#         sse_algorithm     = "aws:kms"
#       }
#     }
#   }

#   cors_rule = [
#     {
#       allowed_methods = ["PUT", "POST"]
#       allowed_origins = ["https://modules.tf", "https://terraform-aws-modules.modules.tf"]
#       allowed_headers = ["*"]
#       expose_headers  = ["ETag"]
#       max_age_seconds = 3000
#       }, {
#       allowed_methods = ["PUT"]
#       allowed_origins = ["https://example.com"]
#       allowed_headers = ["*"]
#       expose_headers  = ["ETag"]
#       max_age_seconds = 3000
#     }
#   ]

#   lifecycle_rule = [
#     {
#       id      = "log"
#       enabled = true

#       filter = {
#         tags = {
#           some    = "value"
#           another = "value2"
#         }
#       }

#       transition = [
#         {
#           days          = 30
#           storage_class = "ONEZONE_IA"
#           }, {
#           days          = 60
#           storage_class = "GLACIER"
#         }
#       ]

#       #        expiration = {
#       #          days = 90
#       #          expired_object_delete_marker = true
#       #        }

#       #        noncurrent_version_expiration = {
#       #          newer_noncurrent_versions = 5
#       #          days = 30
#       #        }
#     },
#     {
#       id                                     = "log1"
#       enabled                                = true
#       abort_incomplete_multipart_upload_days = 7

#       noncurrent_version_transition = [
#         {
#           days          = 30
#           storage_class = "STANDARD_IA"
#         },
#         {
#           days          = 60
#           storage_class = "ONEZONE_IA"
#         },
#         {
#           days          = 90
#           storage_class = "GLACIER"
#         },
#       ]

#       noncurrent_version_expiration = {
#         days = 300
#       }
#     },
#     {
#       id      = "log2"
#       enabled = true

#       filter = {
#         prefix                   = "log1/"
#         object_size_greater_than = 200000
#         object_size_less_than    = 500000
#         tags = {
#           some    = "value"
#           another = "value2"
#         }
#       }

#       noncurrent_version_transition = [
#         {
#           days          = 30
#           storage_class = "STANDARD_IA"
#         },
#       ]

#       noncurrent_version_expiration = {
#         days = 300
#       }
#     },
#   ]

#   intelligent_tiering = {
#     general = {
#       status = "Enabled"
#       filter = {
#         prefix = "/"
#         tags = {
#           Environment = "dev"
#         }
#       }
#       tiering = {
#         ARCHIVE_ACCESS = {
#           days = 180
#         }
#       }
#     },
#     documents = {
#       status = false
#       filter = {
#         prefix = "documents/"
#       }
#       tiering = {
#         ARCHIVE_ACCESS = {
#           days = 125
#         }
#         DEEP_ARCHIVE_ACCESS = {
#           days = 200
#         }
#       }
#     }
#   }

#   metric_configuration = [
#     {
#       name = "documents"
#       filter = {
#         prefix = "documents/"
#         tags = {
#           priority = "high"
#         }
#       }
#     },
#     {
#       name = "other"
#       filter = {
#         tags = {
#           production = "true"
#         }
#       }
#     },
#     {
#       name = "all"
#     }
#   ]
# }
# =======================================

################################################################################
# # RDS Automated Backups Replication Module
# ################################################################################

# provider "aws" {
#   alias  = "region2"
#   region = local.region2
# }

# module "kms" {
#   source      = "terraform-aws-modules/kms/aws"
#   version     = "~> 1.0"
#   description = "KMS key for cross region automated backups replication"

#   # Aliases
#   aliases                 = [local.name]
#   aliases_use_name_prefix = true

#   key_owners = [data.aws_caller_identity.current.arn]

#   tags = local.tags

#   providers = {
#     aws = aws.region2
#   }
# }



