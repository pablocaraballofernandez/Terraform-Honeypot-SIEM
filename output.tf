output "siem_public_ip" {
  value = aws_instance.elk_siem.public_ip
}

output "siem_private_ip" {
  value = aws_instance.elk_siem.private_ip
}

output "kibana_url" {
  value = "http://${aws_instance.elk_siem.public_ip}:5601"
}

output "honeypot_public_ip" {
  value = aws_instance.honeypot.public_ip
}

output "honeypot_private_ip" {
  value = aws_instance.honeypot.private_ip
}

output "vpc_id" {
  value = aws_vpc.honeycloud.id
}

output "public_subnet_id" {
  value = aws_subnet.public_ip.id
}

output "ssh_siem" {
  value = "ssh -i ~/.ssh/honeycloud-admin ubuntu@${aws_instance.elk_siem.public_ip}"
}

output "ssh_honeypot" {
  value = "ssh -i ~/.ssh/honeycloud-admin ubuntu@${aws_instance.honeypot.public_ip}"
}

output "elastic_password" {
  value     = var.elastic_password
  sensitive = true
}