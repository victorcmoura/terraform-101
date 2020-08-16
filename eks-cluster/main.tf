provider "aws" {
    region = "us-east-2"
}

module "vpc" {
    source = "terraform-aws-modules/vpc/aws"

    name = "eks-vpc"
    cidr = "10.0.0.0/16"

    azs = ["us-east-2a", "us-east-2b", "us-east-2c"]
    public_subnets = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
    private_subnets = ["10.0.3.0/24", "10.0.4.0/24", "10.0.5.0/24"]

    enable_dns_hostnames = true
    enable_dns_support = true

    enable_nat_gateway = true
    single_nat_gateway = true

    tags = {
        "CreatedByTerraform" = true
        "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }

    public_subnet_tags = {
        "kubernetes.io/cluster/${var.cluster_name}" = "shared"
        "kubernetes.io/role/elb" = "1"
    }

    private_subnet_tags = {
        "kubernetes.io/cluster/${var.cluster_name}" = "shared"
        "kubernetes.io/role/internal-elb" = "1"
    }
}

resource "aws_security_group" "worker_group_management" {
    name_prefix = "worker_group_management"
    vpc_id = module.vpc.vpc_id

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"

        cidr_blocks = [
            "10.0.0.0/16"
        ]
    }
}

data "aws_eks_cluster" "cluster" {
    name = module.created_eks_cluster.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
    name = module.created_eks_cluster.cluster_id
}

provider "kubernetes" {
    host = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token = data.aws_eks_cluster_auth.cluster.token
    load_config_file = false
    version = "~> 1.9"
}

module "created_eks_cluster" {
    source = "terraform-aws-modules/eks/aws"
    cluster_name = var.cluster_name
    cluster_version = "1.16"
    subnets = module.vpc.private_subnets
    vpc_id = module.vpc.vpc_id

    worker_groups = [
        {
            name = "worker-group-1"
            instance_type = "t2.micro"
            asg_desired_capacity = 3
            additional_security_group_ids = [aws_security_group.worker_group_management.id]
        }
    ]
}