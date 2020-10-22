# infrastructure

> <b>infrastructure</b> is *Terraform* configuration files to build AWS infrastructure for the creation of a VPC(Virtual Private Cloud) and its underlying resources. By applying the configuration files, resources including 3 subnets of different availability zones, an internet gateway, and a public route table that allow traffic between the internet gateway and anywhere will be created, and the three subnets will have the public route table associated. 

## Run in Local Development

**> *Install Terraform and create an AWS account***
* [Terraform installations](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/aws-get-started)

**> *Configure local AWS profile***
* Install AWS Command Line Interface
  * [AWS CLI Installations](https://docs.aws.amazon.com/cli/latest/userguide/install-linux.html)
  <br>
* Generate access keys from [My Security Credentials](https://console.aws.amazon.com/iam/home?region=us-east-1#/security_credentials). IAM users should have Programmatic access of AmazonVPCFullAccess.
  <br>
* Configure local AWS profile
  * <code>$ aws configure --profile profile-name</code>
  * Enter access keys and region as prompted 

**> *Set environment variables(use <code>export TF_VAR_<var_below></code> command on Linux/Unix)***
* <code>profile</code> String. Name of local AWS Authenticated profile
* <code>region</code> String. Region associated with the profile
* <code>vpc_cidr</code> String. CIDR block for the VPC
* <code>subs_cidr</code> Map. CIDR blocks for subnets
* <code>ava_zones</code> Map. Availability zones under the region. map keys must be consistent with those of subs_cidr
* <code>public_key_path</code> String. Path of your ssh public key
* <code>ssh_key_name</code> String. Name of the ssh public key
* <code>ami</code> String. AMI id upon which an EC2 instance will be created for testing
* <code>instance_type</code> String. EC2 instance type
* <code>sub_id</code> String. Subnet id where the EC2 instance get launched
* <code>b_name</code> String. S3 bucket name
* <code>db_identifier</code> String. RDS database identifier
* <code>db_name</code> String. RDS database name
* <code>db_uname</code> String. RDS master username
* <code>db_pwd</code> String. RDS master password
* <code>db_subs_name</code> String. Name of subnet group for the database instance
* <code>dynamodb_tbl_name</code> String. Dynamodb table name
* <code>iam_p_name</code> String. Name of IAM police
* <code>iam_r_name</code> String. Name of IAM role
* <code>AWS_ACCESS_KEY_ID</code> String. AWS access ID for the EC2 instance running the application
* <code>AWS_SECRET_ACCESS_KEY</code> String. AWS secret key for the EC2 instance running the application

**> *Create a VPC and its rescources***

    $ cd <repo-root>
    $ terraform init
    $ terraform validate    # proceed if no errors found
    $ terraform apply  

**> *Destroy a previous VPC and its rescources***
    
    $ cd <repo-root>
    $ terraform destroy