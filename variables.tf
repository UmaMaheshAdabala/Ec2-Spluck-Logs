variable "vpc_cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  type    = string
  default = "10.0.1.0/24"
}

variable "availability_zone" {
  type    = string
  default = "us-east-1a"
}

variable "ec2_ami" {
  type    = string
  default = "ami-0cae6d6fe6048ca2c"
}
variable "ec2_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "splunk_url" {
  type    = string
  default = "http://44.213.121.228:8088/services/collector/event"
}

variable "splunk_token" {
  type    = string
  default = "f4835653-dd9b-428f-b0ab-19256b1def56"
}
