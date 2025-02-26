resource "aws_security_group" "default" {
  name        = "${var.tags["Environment"]}-default-sg"
  description = "Default security group to allow inbound/outbound from the VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = "true"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-default-sg"
    }
  )
}