terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 3.0"
    }
  }
}

resource "aws_instance" "honeypot" {
  ami = var.ami
  instance_type = var.honeypot_instance_type
  subnet_id = aws_subnet.public_ip.id
  vpc_security_group_ids = [aws_security_group.honeypot.id]
  key_name = aws_key_pair.admin.key_name

  user_data = templatefile("${path.module}/scripts/setup_honeypot.sh.tpl", {
    enable_cowrie = var.enable_cowrie
    enable_dionaea  = var.enable_dionaea
    enable_web_honeypot = var.enable_web_honeypot
    siem_private_ip = aws_instance.elk_siem.private_ip
  })

  provisioner "file" {
    source = "${path.module}/scripts/install_cowrie.sh.tpl"
    destination = "/tmp/install_cowrie.sh"
  }

  provisioner "file" {
  source = "${path.module}/scripts/install_dionaea.sh.tpl"
  destination = "/tmp/install_dionaea.sh"
}

  provisioner "file" {
    source      = "${path.module}/scripts/install_web_honeypot.sh.tpl"
    destination = "/tmp/install_web_honeypot.sh"
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/install_filebeat.sh.tpl", {
      siem_private_ip = aws_instance.elk_siem.private_ip
      enable_cowrie = var.enable_cowrie
      enable_dionaea = var.enable_dionaea
      enable_web_honeypot = var.enable_web_honeypot
    })
    destination = "/tmp/install_filebeat.sh"
  }

  connection {
    type = "ssh"
    user = "ubuntu"
    private_key = file(pathexpand("~/.ssh/honeycloud-admin"))
    host = self.public_ip
  }

  depends_on = [ aws_instance.elk_siem ]
}

resource "aws_instance" "elk_siem" {
  ami = var.ami
  instance_type = var.elk_instance_type
  subnet_id = aws_subnet.public_ip.id
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.elk.id]
  key_name = aws_key_pair.admin.key_name

  root_block_device{
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/setup_elk.sh.tpl", {
    cluster_name = var.project_name
    elastic_password = var.elastic_password
    node_name = "elk-node"
    network_host = "0.0.0.0/0"
  })
}
resource "aws_key_pair" "admin" {
  key_name   = "${var.project_name}-admin-key"
  public_key = var.ssh_public_key
}
