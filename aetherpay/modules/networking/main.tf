# =============================================================================
# Networking Module — Main Configuration
# =============================================================================
# Creates the complete network layer for one region.
# This module is called once for the primary region and once for the secondary.
# All resource names are prefixed with project_name and environment so resources
# from both regions can coexist in the same AWS account without name collisions.
# =============================================================================

# -----------------------------------------------------------------------------
# Data — Availability Zones
# -----------------------------------------------------------------------------
# Fetches the actual available AZ names in the current region at plan time.
# This avoids hardcoding AZ names like "us-east-1a" which can vary per account.
data "aws_availability_zones" "available" {
  state = "available" # Only return AZs that are currently available
}

# Convenience local: pick the first three available AZs.
# We index into this list when creating subnets.
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Required for VPC endpoints and ECS task DNS resolution to work correctly.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# -----------------------------------------------------------------------------
# Public Subnets — one per AZ
# -----------------------------------------------------------------------------
# Public subnets host ALBs and NAT Gateways.
# Resources here can receive public IP addresses and are reachable from the internet
# via the Internet Gateway.
resource "aws_subnet" "public" {
  count = 3

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  # Do NOT assign public IPs by default. ALBs and NAT Gateways get Elastic IPs
  # explicitly — we do not want every resource in this subnet to be public.
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-${var.environment}-public-${local.azs[count.index]}"
    Tier = "public"
  }
}

# -----------------------------------------------------------------------------
# Private Application Subnets — one per AZ
# -----------------------------------------------------------------------------
# ECS Fargate tasks run here. No public IPs. No direct internet route.
# AWS service traffic uses VPC endpoints. These subnets are isolated from
# the internet but can communicate with the isolated DB tier via security groups.
resource "aws_subnet" "private_app" {
  count = 3

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  map_public_ip_on_launch = false # ECS tasks must never receive public IPs

  tags = {
    Name = "${var.project_name}-${var.environment}-private-app-${local.azs[count.index]}"
    Tier = "private-app"
  }
}

# -----------------------------------------------------------------------------
# Isolated Database Subnets — one per AZ
# -----------------------------------------------------------------------------
# Aurora PostgreSQL runs here. Completely isolated — no internet route of any kind.
# Only accepts inbound traffic from the private application subnets via security groups.
resource "aws_subnet" "isolated_db" {
  count = 3

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.isolated_db_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  map_public_ip_on_launch = false # Databases must never have public IPs

  tags = {
    Name = "${var.project_name}-${var.environment}-isolated-db-${local.azs[count.index]}"
    Tier = "isolated-db"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------
# Attaches to the VPC and provides the path between public subnets and the internet.
# Only public subnets route through this gateway.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# -----------------------------------------------------------------------------
# Elastic IPs for NAT Gateways — one per AZ
# -----------------------------------------------------------------------------
# Each NAT Gateway requires a static public IP address.
# We create one EIP per AZ so each NAT Gateway has its own IP.
resource "aws_eip" "nat" {
  count = 3

  domain = "vpc" # Allocate the EIP in the VPC scope (required for NAT Gateways)

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-eip-${local.azs[count.index]}"
  }

  # The EIP depends on the Internet Gateway existing first.
  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# NAT Gateways — one per AZ
# -----------------------------------------------------------------------------
# NAT Gateways sit in public subnets and allow resources in private subnets to
# initiate outbound connections to the internet (e.g. third-party payment APIs)
# without being directly reachable from the internet.
#
# One per AZ ensures that if one AZ fails, the other AZs still have egress.
# If we used a single NAT Gateway, an AZ failure would break egress for all AZs.
#
# IMPORTANT: These NAT Gateways are NOT added as default routes for the private
# application subnets. ECS tasks use VPC endpoints for AWS service traffic.
# NAT routes are only added to the public subnet route tables.
# Add a NAT route to private app subnets only if your application needs to reach
# a specific third-party internet endpoint that cannot use a VPC endpoint.
resource "aws_nat_gateway" "main" {
  count = 3

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id # NAT Gateways live in public subnets

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-${local.azs[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# Route Tables
# =============================================================================

# -----------------------------------------------------------------------------
# Public Route Table
# -----------------------------------------------------------------------------
# One shared route table for all three public subnets.
# Routes all internet-bound traffic through the Internet Gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # Default route: all traffic not destined for the VPC CIDR goes to the IGW.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

# Associate each public subnet with the public route table.
resource "aws_route_table_association" "public" {
  count = 3

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Private Application Route Tables — one per AZ
# -----------------------------------------------------------------------------
# Each private app subnet gets its own route table.
# These route tables have NO default internet route.
# AWS service traffic is handled by VPC endpoints (added automatically when
# the endpoint is associated with this route table for Gateway endpoints,
# or via DNS for Interface endpoints).
#
# We create one per AZ (not one shared) so that if you later need to add a
# NAT route for a specific AZ, you can do so without affecting the others.
resource "aws_route_table" "private_app" {
  count = 3

  vpc_id = aws_vpc.main.id

  # No default route here intentionally.
  # VPC endpoint routes are injected automatically by AWS for Gateway endpoints (S3).
  # Interface endpoints use DNS — no route table entry needed.

  tags = {
    Name = "${var.project_name}-${var.environment}-private-app-rt-${local.azs[count.index]}"
  }
}

# Associate each private app subnet with its own route table.
resource "aws_route_table_association" "private_app" {
  count = 3

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# -----------------------------------------------------------------------------
# Isolated Database Route Tables — one per AZ
# -----------------------------------------------------------------------------
# Isolated subnets have no routes at all beyond the local VPC CIDR.
# No internet gateway, no NAT gateway, no VPC endpoint routes.
# Aurora only needs to be reachable from the private app subnets within the VPC.
resource "aws_route_table" "isolated_db" {
  count = 3

  vpc_id = aws_vpc.main.id

  # No routes added. The implicit local route (VPC CIDR) is always present.

  tags = {
    Name = "${var.project_name}-${var.environment}-isolated-db-rt-${local.azs[count.index]}"
  }
}

# Associate each isolated DB subnet with its own route table.
resource "aws_route_table_association" "isolated_db" {
  count = 3

  subnet_id      = aws_subnet.isolated_db[count.index].id
  route_table_id = aws_route_table.isolated_db[count.index].id
}

# =============================================================================
# Security Groups
# =============================================================================
# Security groups act as virtual firewalls. We create one per logical role so
# that rules are easy to reason about and audit.

# -----------------------------------------------------------------------------
# ALB Security Group
# -----------------------------------------------------------------------------
# The Application Load Balancer sits in public subnets and accepts HTTPS traffic
# from the internet. It only allows inbound 443. Outbound goes to ECS tasks.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Controls traffic to and from the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # Allow HTTPS from anywhere — this is the public-facing entry point.
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP from anywhere — used only to redirect to HTTPS via ALB listener rule.
  ingress {
    description = "HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound from the ALB so it can forward requests to ECS tasks.
  # The ECS task security group restricts which inbound traffic it accepts.
  egress {
    description = "All outbound from ALB to targets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }
}

# -----------------------------------------------------------------------------
# ECS Task Security Group
# -----------------------------------------------------------------------------
# ECS Fargate tasks run in private app subnets. They only accept traffic from
# the ALB security group — not from the internet directly.
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-${var.environment}-ecs-tasks-sg"
  description = "Controls traffic to ECS Fargate tasks. Only accepts traffic from the ALB."
  vpc_id      = aws_vpc.main.id

  # Accept application traffic only from the ALB security group.
  # Port 8080 is the assumed application container port — adjust if your app uses a different port.
  ingress {
    description     = "Application traffic from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # Only the ALB can send traffic here
  }

  # Allow all outbound from ECS tasks.
  # In practice, outbound goes to VPC endpoints (AWS services) or the isolated DB tier.
  # The isolated DB security group restricts what it accepts inbound.
  egress {
    description = "All outbound from ECS tasks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-tasks-sg"
  }
}

# -----------------------------------------------------------------------------
# Aurora Security Group
# -----------------------------------------------------------------------------
# Aurora PostgreSQL runs in isolated subnets. It only accepts PostgreSQL traffic
# (port 5432) from the ECS task security group.
resource "aws_security_group" "aurora" {
  name        = "${var.project_name}-${var.environment}-aurora-sg"
  description = "Controls access to Aurora PostgreSQL. Only accepts traffic from ECS tasks."
  vpc_id      = aws_vpc.main.id

  # Accept PostgreSQL connections only from ECS tasks.
  ingress {
    description     = "PostgreSQL from ECS tasks only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  # No outbound rules — Aurora does not need to initiate outbound connections.
  egress {
    description = "No outbound traffic from Aurora"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["127.0.0.1/32"] # Effectively blocks all outbound
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-sg"
  }
}

# -----------------------------------------------------------------------------
# VPC Endpoint Security Group
# -----------------------------------------------------------------------------
# Interface VPC endpoints (ECR, CloudWatch Logs, Secrets Manager, KMS, SQS)
# need a security group. ECS tasks connect to these endpoints over HTTPS (443).
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-${var.environment}-vpc-endpoints-sg"
  description = "Controls traffic to Interface VPC endpoints. Accepts HTTPS from private app subnets."
  vpc_id      = aws_vpc.main.id

  # Accept HTTPS from the private application subnet CIDRs.
  # ECS tasks call AWS APIs (ECR, CloudWatch, Secrets Manager, KMS, SQS) over HTTPS.
  ingress {
    description = "HTTPS from private app subnets to VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  egress {
    description = "All outbound from VPC endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc-endpoints-sg"
  }
}

# =============================================================================
# VPC Endpoints
# =============================================================================
# VPC endpoints allow ECS tasks in private subnets to reach AWS services
# without traffic leaving the AWS network. This is more secure and cheaper
# than routing through a NAT Gateway.
#
# Gateway endpoints (S3): free, inject routes into route tables.
# Interface endpoints (everything else): hourly cost, use private DNS.

# -----------------------------------------------------------------------------
# S3 Gateway Endpoint
# -----------------------------------------------------------------------------
# ECR stores container image layers in S3. ECS tasks pull these layers when
# starting a new task. Without this endpoint, image pulls would fail because
# private subnets have no internet route.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway" # Gateway endpoints are free and use route table entries

  # Associate with all private app route tables so ECS tasks can reach S3.
  route_table_ids = aws_route_table.private_app[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-endpoint"
  }
}

# -----------------------------------------------------------------------------
# ECR API Interface Endpoint
# -----------------------------------------------------------------------------
# ECS tasks call the ECR API to authenticate and get image manifest information
# before pulling layers. This endpoint handles the API calls.
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true # Allows existing ECR API calls to resolve to the private endpoint

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr-api-endpoint"
  }
}

# -----------------------------------------------------------------------------
# ECR Docker Interface Endpoint
# -----------------------------------------------------------------------------
# ECS tasks pull the actual container image layers through this endpoint.
# Works together with the ECR API endpoint and the S3 Gateway endpoint.
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr-dkr-endpoint"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Logs Interface Endpoint
# -----------------------------------------------------------------------------
# ECS tasks send application logs to CloudWatch Logs via the awslogs log driver.
# Without this endpoint, log delivery would fail in private subnets.
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudwatch-logs-endpoint"
  }
}

# -----------------------------------------------------------------------------
# Secrets Manager Interface Endpoint
# -----------------------------------------------------------------------------
# ECS tasks retrieve database credentials and API keys from Secrets Manager
# at startup. Without this endpoint, secret retrieval would fail.
resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-secrets-manager-endpoint"
  }
}

# -----------------------------------------------------------------------------
# KMS Interface Endpoint
# -----------------------------------------------------------------------------
# Secrets Manager uses KMS to encrypt secrets. ECS tasks call KMS to decrypt
# secrets retrieved from Secrets Manager. Without this endpoint, decryption fails.
resource "aws_vpc_endpoint" "kms" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-kms-endpoint"
  }
}

# -----------------------------------------------------------------------------
# SQS Interface Endpoint
# -----------------------------------------------------------------------------
# ECS tasks publish and consume messages from SQS queues.
# Without this endpoint, SQS calls would fail in private subnets.
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-sqs-endpoint"
  }
}

# -----------------------------------------------------------------------------
# ECS Interface Endpoint
# -----------------------------------------------------------------------------
# Required for the ECS control plane to communicate with Fargate tasks
# in private subnets (task registration, health reporting).
resource "aws_vpc_endpoint" "ecs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-endpoint"
  }
}
