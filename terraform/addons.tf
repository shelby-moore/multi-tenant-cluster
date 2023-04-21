module "eks_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints/modules/kubernetes-addons"

  eks_cluster_id       = module.eks.cluster_name
  eks_cluster_endpoint = module.eks.cluster_endpoint
  eks_oidc_provider    = module.eks.oidc_provider
  eks_cluster_version  = module.eks.cluster_version

  enable_argocd         = true
  argocd_manage_add_ons = true
  argocd_helm_config = {
    name             = "argocd"
    chart            = "argo-cd"
    repository       = "https://argoproj.github.io/argo-helm"
    version          = "5.29.1"
    namespace        = "argocd"
    timeout          = "1200"
    create_namespace = true
    values           = [templatefile("helm/argocd-values.yaml", {})]
    set_sensitive = [
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt_hash.argocd.id
      }
    ]
  }

  argocd_applications = {
    addons = {
      path = "bootstrapping/applications"
      repo_url = "https://github.com/shelby-moore/multi-tenant-cluster.git"
      type = "kustomize"
      add_on_application = true
    }
  }

  // Because we're using argocd_manage_add_ons above, the booleans below
  // will only result in necessary AWS resources for the components being created.
  enable_aws_load_balancer_controller = true
  enable_cilium = true
  //enable_karpenter = true //We use the karpenter module instead. Enabling here is problematic, the AWS resources are created, but so is the service account, dispite gitops being enabled.
  enable_gatekeeper = true
  //enable_traefik = true //Enabling this would create the traefik ns only, which we're doing using gitops instead. No AWS resources involved.
  
  tags = local.tags
}

# TODO remove this, disable admin user, only use OIDC for access to argocd
resource "random_password" "argocd" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "bcrypt_hash" "argocd" {
  cleartext = random_password.argocd.result
}

resource "aws_secretsmanager_secret" "argocd" {
  name                    = "argocd"
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result
}
