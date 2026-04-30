variable "region" {
    description = "region"
    type = string
    sensitive = true
}

variable "admin_IP" {
    description = "admin_IP"
    type = list(string)
    sensitive = true
}

variable "honeypot_instance_type" {
    description = "honeypot_instance_type "
    type = string
    sensitive = true
}

variable "elk_instance_type" {
    description = "elk_instance_type"
    type = string
    sensitive = true
}

variable "enable_cowrie" {
    description = "enable_cowrie"
    type = bool
    sensitive = true
}

variable "ami" {
    description = "ami_ubuntu"
    type = string
    sensitive = true
}

variable "enviroment" {
    description = "enviroment"
    type = string
    sensitive = true
}

variable "project_name" {
    description = "project_name"
    type = string
    sensitive = true
}

variable "enable_dionaea" {
    description = "enable_dionaea"
    type = bool
    sensitive = true
}

variable "enable_web_honeypot" {
    description = "enable_web_honeypot"
    type = bool
    sensitive = true
}

variable "ssh_public_key" {
    description = "ssh_public_key"
    type = string
    sensitive = true
}


variable "kibana_basic_auth_user" {
    description = "kibana_basic_auth_user"
    type = string
    sensitive = true
}

variable "elastic_password" {
    description = "elastic_password"
    type = string
    sensitive = true
}