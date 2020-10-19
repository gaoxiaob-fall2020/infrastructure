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
    Name = "b_key_${timestamp()}_tf"
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

resource "aws_db_subnet_group" "db_subs" {
  name       = "db_subs"
  subnet_ids = [for sub in aws_subnet.subs : sub.id]

  # tags = {
  #   Name = "My DB subnet group"
  # }
}

resource "aws_db_instance" "db_instance" {
  allocated_storage = 10
  engine            = "mysql"
  # engine_version         = "5.6.17"
  instance_class         = "db.t3.micro"
  multi_az               = false
  identifier             = "csye6225-f20"
  name                   = "csye6225"
  username               = "csye6225fall2020"
  password               = "Airw0rd640!"
  db_subnet_group_name   = aws_db_subnet_group.db_subs.id
  vpc_security_group_ids = [aws_security_group.sg_db.id]
  # publicly_accessible    = false
  skip_final_snapshot = true
}

resource "aws_key_pair" "ec2_key" {
  key_name   = var.ssh_key_name
  public_key = file(var.public_key_path)
}

resource "aws_instance" "app_instance" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.subs[var.sub_id].id
  vpc_security_group_ids = [aws_security_group.sg_app.id]
  depends_on             = [aws_db_instance.db_instance]
  # disable_api_termination
  root_block_device {
    volume_type = "gp2"
    volume_size = 20
    # delete_on_termination
  }
  user_data = <<-EOF
    #!/bin/bash
    echo "export DEV_ENV=1" >> /etc/profile
    echo "export MYSQL_DB_NAME=csye6225" >> /etc/profile
    echo "export MYSQL_UNAME=csye6225fall2020" >> /etc/profile
    echo "export MYSQL_PWD=Airw0rd640!" >> /etc/profile
    echo "export MYSQL_HOST=${aws_db_instance.db_instance.address}" >> /etc/profile
    echo "export MYSQL_PORT=3306" >> /etc/profile
	EOF
  key_name  = aws_key_pair.ec2_key.key_name
}

resource "aws_dynamodb_table" "dynamodb_tbl" {
  name           = "csye6225"
  hash_key       = "id"
  write_capacity = 5
  read_capacity  = 5

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_policy" "iam_p" {
  name = "WebAppS3"
  # path        = "/"
  description = "IAM policy for EC2 instances to perform S3 buckets"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.b.arn}",
        "${aws_s3_bucket.b.arn}/*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role" "iam_r" {
  name = "EC2-CSYE6225"

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
