# Tenant Helm Chart

This Helm chart is installed using an ArgoCD ApplicationSet, which is configured to create the namespace for the tenant. The Helm chart takes care of installing a set of Kubernetes resources required to isolate the tenant from other tenants in the cluster.

## RBAC

A Kubernetes Role is created with full edit access to the entire namespace, with the exception of Daemonsets. It may be preferable to adapt this role to optionally be created with readonly access in production environments, with edit access being reserved for non-production environments.

A Kubernetes RoleBinding is created that binds the above role to a Group named `eks-TENANTNAME-developers` (TENANTNAME is replaced with the name passed to the Helm chart). The assumption here is that a group with the same name is created in Okta, with the developers that should have access to the tenant namespace added to this group. The kubeconfig for developers should look similar to:

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
    user: TENANTNAME-developer
  name: TENANTNAME-developer@eks-blueprint
current-context: TENANTNAME-developer@eks-blueprint
kind: Config
preferences: {}
users:
- name: TENANTNAME-developer
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

When a developer with the above kubeconfig runs a kubectl command, the kubectl `oidc-login` plugin will open the browser so that the developer can login to Okta. Okta will return a token to the plugin, which can then be used to access the Kubernetes API with kubectl (assuming the Kubernetes API has been configured to use the configured Okta application as an OIDC token issuer).

## Cilium Network Policy

A CiliumNetworkPolicy is applied to the entire tenant namespace that denies all ingress and egress by default, _except_ for egress to KubeDNS. A Kyverno policy is setup for the namespace the prevents this network policy from being modified, except for by cluster admins.

All tenant workloads should create their own CiliumNetworkPolicy if additional ingress/egress rules are required. A Kyverno policy prevents workload policies from allowing ingress/egress to/from other namespaces. Another Kyverno policy prevents tenant workloads from using `hostNetwork`, as the tenant namespace CiliumNetworkPolicy would not apply to these workloads.

A valuable addition would be to setup continuous, automated testing to ensure the network policies applied to the cluster do not provide unintended access to or from tenant namespaces.

## Resource Quota

A ResourceQuota is applied to the tenant namespace so that tenant workloads will not get unbounded access to the cluster. When a ResourceQuota is applied to a namespace, all pods created within that namespace *must* have resource requests and limits specified.

* Note - in addition to a ResourceQuota, it may be desireable to impose a LimitRange on the namespace as well. The settings for the LimitRange would depend on the instance types supported for the node group(s) tenant workloads may be scheduled on. A Kyverno policy could be added to ensure the ResourceQuota/LimitRange are not modified or removed.

* Note - employing QoS classes could be used to guard against workload eviction when a node is having resource contention issues. This is fairly implicit though, as it is set depending on how resource requests and limits are specificed for each workload. The implicit nature could be abstracted away behind Helm values for the tenant workloads. Building on QoS further, it is possible to configure the CPU and Memory Managers such that workloads with the `Guaranteed` QoS class are provided with stronger guarantees of requested CPU and memory.

## Node Group (Optional)

To further mitigate resource starvation type problems from other tenants, the Helm chart supports opting in to have a dedicated node group created for tenant workloads. This node group is managed using a Karpenter Provisioner and AWSNodeTemplate. When a dedicated node group is enabled, a Kyverno policy is created to validate that all tenant workloads include the nodeSelector and toleration needed to use the dedicated node group.

* Note - depending on what external access to resources (to the internet, AWS resources), it may be desireable to modify the Helm chart such that the dedicated node group can use different AWS Security Groups than other node groups.

## Other Considations/Future Additions

### Pod Priority

Depending on the tenants using the cluster, pod priority could be added so that tenant workloads that have less tolerance for downtime are prioritized over tenant workloads that have more tolerance. For example, one tenant may mostly run scheduled batch jobs for internal reporting purposes, while another tenant runs web applications accessed by end users. By applying a higher pod priority to the latter tenant, we could better support HA by evicting the former tenant's workloads when the cluster is under resource pressure. ResourceQuotas can be used to restrict which namespaces can use a priority class.

* Note - it may be desireable to add a Kyverno policy to ensure only certain priority classes are used. For example, tenant workloads should likely not use the `system-cluster-critical` and `system-node-critical` priority classes.

### Ingress

Depending on the level of isolation needed between tenants, it may be desireable to setup an Ingress Controller per tenant. This would make it possible to isolate all incoming network traffic per tenant to a dedicated ingress node group. Unexpected traffic patterns for one tenant would not impact the other tenants.

### ArgoCD AppProject

Depending on the level of isolation needed between tenants, it may be desireable to setup an ArgoCD AppProject per tenant. This would allow control over what resources a tenant can deploy and the destination namespace resources are deployed to. Tenant developers could be given access to only their associated AppProject in the ArgoCD UI/CLI using a role associated with the AppProject that is mapped to their Okta group.
