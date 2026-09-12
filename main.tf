provider "aws" {
  region = "us-east-1"
}

resource "aws_db_subnet_group" "this" {
  name       = "mecanica-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "mecanica-db-subnet-group"
  }
}

resource "aws_security_group" "this" {
  name   = "mecanica-db-sg"
  vpc_id = var.vpc_id
  ingress {
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [var.allowed_security_group_id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mecanica-db-sg"
  }
}

resource "random_password" "this" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "this" {
  name                    = "mecanica-db-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.this.result
    dbname   = var.db_name
    port     = var.db_port
    host     = aws_db_instance.this.address
  })
}

resource "aws_db_instance" "this" {
  identifier             = "mecanica-db-prod"
  db_name                = var.db_name
  engine                 = "postgres"
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  username               = var.db_username
  password               = random_password.this.result
  port                   = var.db_port
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = var.publicly_accessible
  skip_final_snapshot    = var.skip_final_snapshot
  multi_az               = var.multi_az
  apply_immediately      = true
}