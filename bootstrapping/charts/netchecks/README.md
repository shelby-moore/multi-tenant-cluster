# Experimental Installation of NetChecks

See [https://github.com/hardbyte/netchecks/blob/main/operator/README.md#installation](https://github.com/hardbyte/netchecks/blob/main/operator/README.md#installation).

I took the CRDs in [https://raw.githubusercontent.com/kubernetes-sigs/wg-policy-prototypes/master/policy-report/crd/v1alpha2/wgpolicyk8s.io_policyreports.yaml](https://raw.githubusercontent.com/kubernetes-sigs/wg-policy-prototypes/master/policy-report/crd/v1alpha2/wgpolicyk8s.io_policyreports.yaml)
 and put them in [./templates](templates).

I took the static manifests in [https://github.com/hardbyte/netchecks/blob/main/operator/README.md#static-manifests](https://github.com/hardbyte/netchecks/blob/main/operator/README.md#static-manifests) and put them in [./templates](templates). Once the Helm chart is publicly available, switch to it.
