Yes — that is the clean way to do it.

For MetalLB in prod, the usual flow is:
	1.	Export everything from the current release
	2.	Pull the target chart locally
	3.	Render the target using your current prod values
	4.	Compare current vs target
	5.	Check API versions / CRDs / objects changed

That lets you compare safely without changing prod yet. Helm can pull and render charts locally, so you can do this even from a machine with just Helm installed. helm template renders locally and does not need a cluster connection, while helm get manifest and helm get values read the currently installed release from the cluster.  ￼

Simple workflow

Assume:
	•	release name: metallb
	•	namespace: metallb-system
	•	target chart: metallb/metallb
	•	target version: for example 0.15.3

MetalLB’s official docs show installation from the metallb Helm repo, and its configuration is done through Kubernetes resources such as IPAddressPool and L2Advertisement in the MetalLB namespace.  ￼

1) Export current prod release

Run this on a machine that has kubectl/helm access to prod:

mkdir -p ~/metallb-compare/prod
cd ~/metallb-compare/prod

RELEASE=metallb
NS=metallb-system

helm get values $RELEASE -n $NS -a -o yaml > current-values-all.yaml
helm get manifest $RELEASE -n $NS > current-manifest.yaml
helm get all $RELEASE -n $NS > current-release-all.txt

kubectl get all -n $NS -o yaml > ns-all.yaml
kubectl get cm,secret,svc,deploy,ds,job -n $NS -o yaml > ns-core-objects.yaml
kubectl get crd | grep -i metallb > current-crd-list.txt || true
kubectl get ipaddresspools,l2advertisements,bgppeers,bfdprofiles -n $NS -o yaml > metallb-crs.yaml 2>/dev/null || true

2) Pull the target chart locally

This can be done from your WSL or any box with Helm only:

mkdir -p ~/metallb-compare/target
cd ~/metallb-compare/target

helm repo add metallb https://metallb.github.io/metallb
helm repo update

helm pull metallb/metallb --version 0.15.3 --untar

The MetalLB docs publish the Helm repo and standard install method.  ￼

3) Render the target chart using current prod values

This is the important part.

cd ~/metallb-compare/target

helm template metallb ./metallb \
  -n metallb-system \
  -f ../prod/current-values-all.yaml \
  > target-rendered.yaml

helm template renders locally, so this is a safe offline comparison step. Helm notes that local rendering does not do full server-side API validation unless you explicitly provide API versions.  ￼

4) Compare current vs target

cd ~/metallb-compare

diff -u prod/current-manifest.yaml target/target-rendered.yaml > metallb-diff.patch || true
less metallb-diff.patch

Or easier to read:

vimdiff prod/current-manifest.yaml target/target-rendered.yaml

5) Quick API version comparison

This lets you see if any object API versions changed.

echo "=== CURRENT ==="
grep '^apiVersion:' ~/metallb-compare/prod/current-manifest.yaml | sort | uniq -c

echo "=== TARGET ==="
grep '^apiVersion:' ~/metallb-compare/target/target-rendered.yaml | sort | uniq -c

6) Quick CRD comparison

grep -n 'CustomResourceDefinition' -n ~/metallb-compare/prod/current-manifest.yaml
grep -n 'CustomResourceDefinition' -n ~/metallb-compare/target/target-rendered.yaml

And to see CRD apiVersion only:

awk '
/^kind: CustomResourceDefinition/ {crd=1}
crd && /^apiVersion:/ {print; crd=0}
' ~/metallb-compare/target/target-rendered.yaml

7) Optional: compare default chart values too

This helps you see newly introduced settings:

helm show values metallb/metallb --version 0.15.3 > ~/metallb-compare/target/default-values-0.15.3.yaml
diff -u ~/metallb-compare/prod/current-values-all.yaml ~/metallb-compare/target/default-values-0.15.3.yaml || true

helm get values retrieves the installed release values, while values files are one of the core inputs Helm uses during rendering.  ￼

In short

Yes, your process is basically:
	•	export current prod release
	•	pull target chart
	•	render target with current prod values
	•	compare manifests
	•	review API versions, CRDs, and config CRs

Important note

MetalLB configuration like IPAddressPool and L2Advertisement is usually managed as Kubernetes resources in the MetalLB namespace, not just Helm values, so export those CRs too or your comparison will miss part of the real prod state. MetalLB’s docs explicitly describe configuration through these resources in the same namespace where MetalLB is deployed.  ￼

Recommended command pack

Here is a compact version you can reuse:

# ===== on prod-connected host =====
mkdir -p ~/metallb-compare/prod
cd ~/metallb-compare/prod
RELEASE=metallb
NS=metallb-system

helm get values $RELEASE -n $NS -a -o yaml > current-values-all.yaml
helm get manifest $RELEASE -n $NS > current-manifest.yaml
helm get all $RELEASE -n $NS > current-release-all.txt
kubectl get ipaddresspools,l2advertisements,bgppeers,bfdprofiles -n $NS -o yaml > metallb-crs.yaml 2>/dev/null || true

# ===== on WSL or any Helm box =====
mkdir -p ~/metallb-compare/target
cd ~/metallb-compare/target
helm repo add metallb https://metallb.github.io/metallb
helm repo update
helm pull metallb/metallb --version 0.15.3 --untar

helm template metallb ./metallb \
  -n metallb-system \
  -f ../prod/current-values-all.yaml \
  > target-rendered.yaml

cd ~/metallb-compare
diff -u prod/current-manifest.yaml target/target-rendered.yaml > metallb-diff.patch || true
grep '^apiVersion:' prod/current-manifest.yaml | sort | uniq -c
grep '^apiVersion:' target/target-rendered.yaml | sort | uniq -c

If you want, I’ll turn this into a single bash script that does:
	•	export from prod
	•	pull target version
	•	render target
	•	compare
	•	print a simple compatibility summary score