provider "aws" {
  profile = var.profile
  region  = var.region
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc_${timestamp()}_tf"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "igw_${timestamp()}_tf"
  }
}

resource "aws_subnet" "subs" {
  for_each                = var.subs_cidr
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = var.ava_zones[each.key]
  tags = {
    Name = "${each.key}-${aws_vpc.vpc.tags.Name}"
  }
}

resource "aws_route_table" "rtb" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "rtb_${timestamp()}_tf"
  }
}

resource "aws_route_table_association" "rta_for_subs" {
  for_each       = var.subs_cidr
  subnet_id      = aws_subnet.subs[each.key].id
  route_table_id = aws_route_table.rtb.id
}

resource "aws_security_group" "sg_22" {
  name   = "sg_22"
  vpc_id = aws_vpc.vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "sg_${timestamp()}_tf"
  }
}

resource "aws_security_group" "sg_app" {
  name   = "application"
  vpc_id = aws_vpc.vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "sg_app_${timestamp()}_tf"
  }
}

resource "aws_security_group" "sg_db" {
  name   = "database"
  vpc_id = aws_vpc.vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_app.id]
  }
  tags = {
    Name = "sg_db_${timestamp()}_tf"
  }
}

resource "aws_kms_key" "s3_key" {
  description             = "This key is used to encrypt bucket objects"
  deletion_window_in_days = 10
  tags = {
    Alias = "b_key_${timestamp()}_tf"
  }
}

resource "aws_s3_bucket" "b" {
  bucket        = var.b_name
  acl           = "private"
  force_destroy = true

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    prefix  = "30DaysOld/"
    enabled = true
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    noncurrent_version_transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  tags = {
    Name = "b_${timestamp()}_tf"
  }
}

resource "aws_s3_bucket_public_access_block" "b_block_public" {
  bucket = aws_s3_bucket.b.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_db_subnet_group" "db_subs" {
  name       = var.db_subs_name
  subnet_ids = [for sub in aws_subnet.subs : sub.id]
}

resource "aws_db_instance" "db_instance" {
  allocated_storage = 10
  engine            = "mysql"
  # engine_version         = "5.6.17"
  instance_class         = "db.t3.micro"
  multi_az               = false
  identifier             = var.db_identifier
  name                   = var.db_name
  username               = var.db_uname
  password               = var.db_pwd
  db_subnet_group_name   = aws_db_subnet_group.db_subs.id
  vpc_security_group_ids = [aws_security_group.sg_db.id]
  # publicly_accessible    = false
  skip_final_snapshot = true
}

resource "aws_key_pair" "ec2_key" {
  key_name   = var.ssh_key_name
  public_key = file(var.public_key_path)
}

resource "aws_iam_instance_profile" "ins_p" {
  name = var.iam_r_name
  role = aws_iam_role.iam_r.name
}

resource "aws_instance" "app_instance" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.subs[var.sub_id].id
  vpc_security_group_ids = [aws_security_group.sg_app.id]
  iam_instance_profile   = aws_iam_instance_profile.ins_p.name
  depends_on             = [aws_db_instance.db_instance]
  # disable_api_termination
  root_block_device {
    volume_type = "gp2"
    volume_size = 20
    # delete_on_termination
  }

  user_data = <<-EOF
    #!/bin/bash
    echo "export DEV_ENV=1" >> /etc/environment
    echo "export MYSQL_DB_NAME=${aws_db_instance.db_instance.name}" >> /etc/environment
    echo "export MYSQL_UNAME=${aws_db_instance.db_instance.username}" >> /etc/environment
    echo "export MYSQL_PWD=${var.db_pwd}" >> /etc/environment
    echo "export MYSQL_HOST=${aws_db_instance.db_instance.address}" >> /etc/environment
    echo "export MYSQL_PORT=${aws_db_instance.db_instance.port}" >> /etc/environment
    echo "export AWS_S3_BUCKET=${aws_s3_bucket.b.id}" >> /etc/environment
    echo "export LOGGING_FILE_PATH=${var.app_logging_path}" >> /etc/environment
    echo "export LOGGING_LEVEL=${var.app_logging_level}" >> /etc/environment
	EOF

  key_name = aws_key_pair.ec2_key.key_name
  tags = {
    Name = "app_${timestamp()}_tf"
    For  = "app"
  }
}

resource "aws_dynamodb_table" "dynamodb_tbl" {
  name           = var.dynamodb_tbl_name
  hash_key       = "id"
  write_capacity = 5
  read_capacity  = 5

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_policy" "iam_p" {
  name = var.iam_p_name
  # path        = "/"
  description = "IAM policy for EC2 instances to perform S3 buckets(put & delete files, and get app artifacts), and enable CloudWatch"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:GetObject",
        "s3:GetObjectAcl",
        "s3:DeleteObject",
        "kms:GenerateDataKey"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.b.arn}",
        "${aws_s3_bucket.b.arn}/*",
        "${aws_kms_key.s3_key.arn}"
      ]
    },
    {
      "Action": [
          "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::${var.codedeploy_b_name}",
        "arn:aws:s3:::${var.codedeploy_b_name}/*"
      ]
    },
    {
        "Effect": "Allow",
        "Action": [
            "cloudwatch:PutMetricData",
            "ec2:DescribeVolumes",
            "ec2:DescribeTags",
            "logs:PutLogEvents",
            "logs:DescribeLogStreams",
            "logs:DescribeLogGroups",
            "logs:CreateLogStream",
            "logs:CreateLogGroup"
        ],
        "Resource": "*"
    },
    {
        "Effect": "Allow",
        "Action": [
            "ssm:GetParameter"
        ],
        "Resource": "arn:aws:ssm:*:*:parameter/AmazonCloudWatch-*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "iam_r" {
  name = var.iam_r_name

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

resource "aws_iam_role_policy_attachment" "r_p_att" {
  role       = aws_iam_role.iam_r.name
  policy_arn = aws_iam_policy.iam_p.arn
}

resource "aws_instance" "testing" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.subs[var.sub_id].id
  vpc_security_group_ids = [aws_security_group.sg_22.id]
  key_name               = aws_key_pair.ec2_key.key_name
  tags = {
    Name = "${timestamp()}_tf"
  }
}

#####
# resource "aws_iam_user" "gh_cd_user" {
#   name = var.gh_cd_uname
# }

resource "aws_iam_policy" "gh_p1" {
  name        = "GH-Upload-To-S3"
  description = "allows GitHub Actions to upload artifacts from latest successful build to dedicated S3 bucket used by CodeDeploy"
  policy      = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${var.codedeploy_b_name}",
		            "arn:aws:s3:::${var.codedeploy_b_name}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_user_policy_attachment" "att1" {
  user       = var.gh_cd_uname
  policy_arn = aws_iam_policy.gh_p1.arn
}

resource "aws_iam_policy" "gh_p2" {
  name        = "GH-Code-Deploy"
  description = "allows GitHub Actions to call CodeDeploy APIs to initiate application deployment on EC2 instances"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:RegisterApplicationRevision",
        "codedeploy:GetApplicationRevision"
      ],
      "Resource": [
        "arn:aws:codedeploy:${var.region}:${var.account_id}:application:${var.codedeploy_app_name}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:CreateDeployment",
        "codedeploy:GetDeployment"
      ],
      "Resource": [
        "*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:GetDeploymentConfig"
      ],
      "Resource": [
        "arn:aws:codedeploy:${var.region}:${var.account_id}:deploymentconfig:CodeDeployDefault.OneAtATime",
        "arn:aws:codedeploy:${var.region}:${var.account_id}:deploymentconfig:CodeDeployDefault.HalfAtATime",
        "arn:aws:codedeploy:${var.region}:${var.account_id}:deploymentconfig:CodeDeployDefault.AllAtOnce"
      ]
    }
  ]
}
  EOF
}

resource "aws_iam_user_policy_attachment" "att2" {
  user       = var.gh_cd_uname
  policy_arn = aws_iam_policy.gh_p2.arn
}

# output "checkout" {
#   for_each = aws_iam_policy.gh_p1
#   value    = "${each.key} - ${each.value}"
# }

resource "aws_route53_record" "www" {
  zone_id = var.hosted_zone_id
  name    = var.api_subdomain_name
  type    = "A"
  ttl     = "60"
  records = [aws_instance.app_instance.public_ip]
}
