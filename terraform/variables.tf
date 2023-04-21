locals {
  name     = "eks-blueprint"
  region   = "us-west-2"
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  cluster_version = "1.26"

  oidc_okta_client_id = "TOBEDETERMINED"
  oidc_okta_issuer_url = "TOBEDETERMINED"

  tags = {
    Name = local.name
  }
}
