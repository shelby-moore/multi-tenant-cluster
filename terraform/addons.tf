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
      path               = "bootstrapping/applications"
      repo_url           = "https://github.com/shelby-moore/multi-tenant-cluster.git"
      type               = "kustomize"
      add_on_application = true
    }
    workloads = {
      path               = "workloads/applications"
      repo_url           = "https://github.com/shelby-moore/multi-tenant-cluster.git"
      type               = "kustomize"
      add_on_application = false
    }
  }

  // Because we're using argocd_manage_add_ons above, the booleans below
  // will only result in necessary AWS resources for the components being created.

  // This service account name is what the helm chart installation defaults to. However, the IAM trust policy
  // created by the addons terraform uses "aws-load-balancer-controller-sa" by default. We make the change below
  // so the addons terraform changes the trust policy to match the helm chart installation.
  // We use the irsa module instead. Enabling here is problematic, the AWS resources are created, but so is the service account, despite gitops being enabled.
  # enable_aws_load_balancer_controller = true
  # aws_load_balancer_controller_helm_config = {
  #   service_account = "aws-load-balancer-controller"
  # }
  //enable_cilium = true
  //enable_karpenter = true //We use the karpenter module instead. Enabling here is problematic, the AWS resources are created, but so is the service account, despite gitops being enabled.
  //enable_traefik = true //Enabling this would create the traefik ns only, which we're doing using gitops instead. No AWS resources involved.

  tags = local.tags
}

module "aws_load_balancer_controller_irsa" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints/modules/irsa"

  eks_cluster_id                    = module.eks.cluster_name
  eks_oidc_provider_arn             = module.eks.oidc_provider_arn
  kubernetes_namespace              = "kube-system"
  kubernetes_service_account        = "aws-load-balancer-controller"
  create_kubernetes_namespace       = false
  create_kubernetes_service_account = false
  irsa_iam_policies                 = [aws_iam_policy.aws_load_balancer_controller.arn]
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${module.eks.cluster_name}-lb-irsa"
  description = "Allows lb controller to manage ALB and NLB"
  policy      = data.aws_iam_policy_document.aws_lb.json
  tags        = local.tags
}

data "aws_iam_policy_document" "aws_lb" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]
    actions   = ["iam:CreateServiceLinkedRole"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeCoipPools",
      "ec2:DescribeInstances",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeVpcs",
      "ec2:GetCoipPoolUsage",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "cognito-idp:DescribeUserPoolClient",
      "iam:GetServerCertificate",
      "iam:ListServerCertificates",
      "shield:CreateProtection",
      "shield:DeleteProtection",
      "shield:DescribeProtection",
      "shield:GetSubscriptionState",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]
    actions   = ["ec2:CreateSecurityGroup"]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:ec2:*:*:security-group/*"]
    actions   = ["ec2:CreateTags"]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:ec2:*:*:security-group/*"]

    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/ingress.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = ""
    effect = "Allow"

    resources = [
      "arn:${data.aws_partition.current.partition}:elasticloadbalancing:*:*:loadbalancer/app/*/*",
      "arn:${data.aws_partition.current.partition}:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:${data.aws_partition.current.partition}:elasticloadbalancing:*:*:targetgroup/*/*",
    ]

    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:RemoveTags",
    ]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/ingress.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:ec2:*:*:security-group/*"]

    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup",
      "ec2:RevokeSecurityGroupIngress",
    ]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
    ]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteRule",
    ]
  }

  statement {
    sid    = ""
    effect = "Allow"

    resources = [
      "arn:${data.aws_partition.current.partition}:elasticloadbalancing:*:*:loadbalancer/app/*/*",
      "arn:${data.aws_partition.current.partition}:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:${data.aws_partition.current.partition}:elasticloadbalancing:*:*:targetgroup/*/*",
    ]

    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = ""
    effect = "Allow"

    resources = [
      "arn:${data.aws_partition.current.partition}:elasticloadbalancing:*:*:listener/net/*/*/*",
      "arn:${data.aws_partition.current.partition}:elasticloadbalancing:*:*:listener/app/*/*/*",
      "arn:${data.aws_partition.current.partition}:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
      "arn:${data.aws_partition.current.partition}:elasticloadbalancing:*:*:listener-rule/app/*/*/*",
    ]

    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
    ]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:elasticloadbalancing:*:*:targetgroup/*/*"]

    actions = [
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:RegisterTargets",
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:SetWebAcl",
    ]
  }
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
  name = "argocd"
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result
}
