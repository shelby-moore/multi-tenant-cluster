module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    # The AWS LB controller uses this to provision public LBs
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = local.name
    # The AWS LB controller uses this to provision private LBs
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}
