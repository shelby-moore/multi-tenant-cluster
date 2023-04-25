# Kyverno Policy Tests

I've added some Kyverno policies to the [tenant helm chart](../bootstrapping/charts/tenant/templates). There is a [huge library of existing policies](https://kyverno.io/policies) that could be pulled in as well!

The policies I've added make sure that:

- The default, namespace-wide CiliumNetworkPolicy for the tenant namespace cannot be modified (except for by a cluster-admin)
- Any additional CiliumNetworkPolicies restrict traffic appropriately:
    - Allow egress to the same namespace
    - Allow egress to kubedns
    - Allow egress to the internet (if using 0.0.0.0/0, 10.0.0.0/8 must be blocked, this would open up access to other pods in the cluster because of how the EKS CNI works)
    - Allow ingress from the same namespace, or from the Traefik private/public ingresses
- If the tenant opts to have a dedicated node group, any pods created in the tenant namespace must have a nodeSelector/toleration for the dedicated node group.

This is by no means a comprehensive set of policies, just a start. They could also very likely (definitely) be written in a more eloquent manner. I'm new to Kyverno, don't judge them too harshly =)

I've added tests for the policies above inside of this directory. They can be run with:

```
brew install kyverno

kyverno test policy-tests/cilium-network-policy/
kyverno test policy-tests/node-group/
```

TODO

- Figure out how to avoid duplicating the policy for the test and inside of the tenant helm chart (eg how can the one on the chart be templated out for the test, helm template ... then kyverno test ...).
