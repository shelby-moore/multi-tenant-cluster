# multi-tenant-cluster

# Setup Okta App for OIDC Access to the Cluster

Follow [https://developer.okta.com/blog/2021/10/08/secure-access-to-aws-eks](https://developer.okta.com/blog/2021/10/08/secure-access-to-aws-eks), creating
the following three groups instead of `eks-admins`:

- eks-cluster-admin
- eks-tenant-one-developers
- eks-tenant-two-developers

Update [the OIDC provider configuration for the EKS cluster we will create below](./terraform/variables.tf) to include the client_id and issuer_url for the OIDC provider you created using the guide linked above.

# Setup EKS Cluster and Addons

Run the commands below to create a new EKS cluster on AWS, with ArgoCD installed. ArgoCD is configured to sync the Applications defined in [bootstrapping/applications](./bootstrapping/applications) to the newly created cluster.

```
terraform init

terraform apply -target=module.vpc
terraform apply -target=module.eks
terraform apply

aws eks --region us-west-2 update-kubeconfig --name eks-blueprint
```

The bootstrapping Applications include:

- AWS Load Balancer Controller - will create load balancers for the Traefik ingresses.
- Cilium - installed in EKS CNI chaining mode, with wireguard encryption enabled. Used for network policy enforcement.
- Cluster Admin RBAC - RBAC to provider cluster admin access to the cluster via Okta OIDC.
- Kyverno - used to enforce policies for Kubernetes resources.
- Karpenter - used to provision nodes.
- Traefik - used to create a public and private ingress for the cluster.

# Cluster Access

As part of bootstrapping above, RBAC is applied to the cluster to bind cluster-admin to the `eks-cluster-admin` Okta group. Use the kubeconfig file below (make sure to update the client_id and issuer_url to your Okta OIDC provider values!) to access the cluster using Okta OIDC.

First, install the kubelogin kubectl plugin, which support OIDC auth.

```
brew install int128/kubelogin/kubelogin
```

Next, update the certificate-authority-data and server fields below to the values for your EKS cluster. Update the client_id and issuer_url to your Okta OIDC provider values. Finally, copy the kubeconfig below to your machine at ~/.kube/config.

```
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: TOBEDETERMINED
    server: TOBEDETERMINED
  name: eks-blueprint
contexts:
- context:
    cluster: eks-blueprint
    user: oidc-cluster-admin
  name: oidc-cluster-admin@eks-blueprint
current-context: oidc-cluster-admin@eks-blueprint
kind: Config
preferences: {}
users:
- name: oidc-cluster-admin      
  user:
    exec:
        apiVersion: client.authentication.k8s.io/v1beta1
        args:
        - oidc-login
        - get-token
        - --oidc-issuer-url=TOBEDETERMINED
        - --oidc-client-id=TOBEDETERMINED
        - --oidc-extra-scope=email
        - --oidc-extra-scope=offline_access
        - --oidc-extra-scope=profile
        - --oidc-extra-scope=openid
        command: kubectl
 ```       

Check that your kubectl access is working. This will open your browser so you can login to Okta (if you're not already logged in).

```
kubectl config use-context oidc-cluster-admin@eks-blueprint
kubectl get pods --all-namespaces
```

To logout, clear the cache, which will trigger the auth flow again.

```
rm -rf ~/.kube/cache/oidc-login
```

# TODO Production Readiness

- Apply network policies to all non-tenant namespaces (kube-system, argocd, cilium-system, karpenter, traefik-private, traefik-public...)
- The private load balancer created by the `traefik-private` installation has an allowlist for the EKS VPC cidr range to the load balancer. This makes testing easy for now, 
as we can call the ingress using a pod in the cluster. However, this should be removed, as it allows pods in the cluster to potentially cirumvent network policy by using the ingress to call other pods in the cluster that would be blocked using in cluster routing.
- Consider pod priority - are any tenants more important than the others?
- Any workloads scheduled before Cilium will not have network policy enforcement applied, as the agent needs to be running when the workload is scheduled to setup a cilium endpoint. This is typically handled by the cilium start up taint on nodes. Bit of a chicken/egg problem if we're applying Cilium with ArgoCD. Maybe use a post sync hook to delete all pods except Cilium on the cluster?
- ArgoCD admin user secret is in the statefile. Setup OIDC access to ArgoCD and disable the admin user.
- Separate Argo Projects, one for bootstrapping, one per tenant (?).
- Pull through cache third-party images.
- Cilium w/ wireguard - it’s important to note that traffic between Pods on the same host are not encrypted. The Cilium team made this decision intentionally because if privilege exists to view traffic on the node, it is possible to view the raw, unencrypted traffic anyway. This is because encryption is done as traffic is leaving the node
through a tunnel device. If this is not acceptable from a security perspective, mutual TLS may be a better option.
- Security hardening - modify RBAC as needed to be least privilege, add pod/container security context
- Reliability hardening - HA, topology spread, affinity, monitoring
- Cost - Karpenter uses spot/on-demand nodes (turn on SQS interruption handling for Karpenter)
