variable "profile" {
  description = "Local AWS authenticated profile"
  default     = "dev"
}

variable "region" {
  description = "Region associated with the porfile"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "172.31.0.0/16"
}

variable "subs_cidr" {
  description = "CIDR blocks for subnets"
  default = {
    "sub1" : "172.31.0.0/24"
    "sub2" : "172.31.1.0/24"
    "sub3" : "172.31.2.0/24"
  }
}

variable "ava_zones" {
  description = "Availability zones"
  default = {
    "sub1" : "us-east-1a"
    "sub2" : "us-east-1b"
    "sub3" : "us-east-1c"
  }
}

variable "public_key_path" {
  description = "Path of public ssh key"
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_key_name" {
  description = "Name of the ssh public key"
  default     = "ssh_public_key"
}

variable "ami" {
  default = "ami-0817d428a6fb68645"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "sub_id" {
  description = "Subnet where the EC2 instance get launched"
  default     = "sub1"
}

variable "environment_tag" {
  description = "Environment tag"
  default     = "Development"
}

variable "b_name" {
  description = "S3 bucket name"
  default     = "webapp.xiaobin.gao"
}
