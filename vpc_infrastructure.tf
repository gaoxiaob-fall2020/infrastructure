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

resource "aws_key_pair" "ec2_key" {
  key_name   = "ssh_public_key"
  public_key = file(var.public_key_path)
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
