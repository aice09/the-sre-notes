Yes — **WSL is fine** for both **skopeo** and **crane**, and for your use case I’d actually prefer **WSL2 Ubuntu** over doing this in plain Windows shell. Microsoft’s current WSL docs use `wsl --install`, and new installs default to **WSL 2**. ([Microsoft Learn][1])

For image mirroring:

* **skopeo** is very strong for **copying/syncing images between registries** and for **air-gapped/internal registry** workflows. Its docs explicitly support copying between registries and syncing external repos into internal registries. ([GitHub][2])
* **crane** is simpler and very nice for quick image operations. The go-containerregistry docs describe `crane pull`, `crane push`, and `crane cp` as the basic read/write/copy flow. ([GitHub][3])

## Which one should you use?

For your case — **download images from public registry and push to local repo for local Kubernetes installer**:

* Use **skopeo** if you want the more “infra/enterprise” style
* Use **crane** if you want the simpler CLI

I’d recommend:

* **skopeo** for bulk mirroring
* **crane** for quick one-by-one copying

---

## 1) Use WSL first

In Windows PowerShell:

```powershell
wsl --install
```

Then open Ubuntu and update packages:

```bash
sudo apt update && sudo apt upgrade -y
```

WSL 2 is the recommended modern path in Microsoft’s docs. ([Microsoft Learn][1])

---

## 2) Install skopeo in WSL

On Ubuntu/Debian-based WSL:

```bash
sudo apt update
sudo apt install -y skopeo jq
```

Check:

```bash
skopeo --version
```

Skopeo’s official project documents that it can inspect, copy, delete, and sync images across registries, and that auth can be done with `skopeo login` or explicit credentials flags. ([GitHub][2])

---

## 3) Basic skopeo usage

### Inspect image without pulling

```bash
skopeo inspect docker://registry.k8s.io/external-dns/external-dns:v0.15.0
```

Skopeo’s docs specifically call out `inspect` as a way to view remote image properties without pulling it locally. ([GitHub][2])

### Login to your local registry

```bash
skopeo login myregistry.local:5000
```

Or for Harbor:

```bash
skopeo login harbor.mydomain.local
```

Skopeo supports credentials via `skopeo login` or `--src-creds` / `--dest-creds` on copy commands. ([GitHub][2])

### Copy image directly from source registry to your local registry

```bash
skopeo copy --all \
  docker://registry.k8s.io/external-dns/external-dns:v0.15.0 \
  docker://myregistry.local:5000/external-dns/external-dns:v0.15.0
```

For MetalLB:

```bash
skopeo copy --all \
  docker://quay.io/metallb/controller:v0.15.2 \
  docker://myregistry.local:5000/metallb/controller:v0.15.2

skopeo copy --all \
  docker://quay.io/metallb/speaker:v0.15.2 \
  docker://myregistry.local:5000/metallb/speaker:v0.15.2
```

For Emissary:

```bash
skopeo copy --all \
  docker://docker.io/emissaryingress/emissary:3.10.2 \
  docker://myregistry.local:5000/emissaryingress/emissary:3.10.2
```

`copy` is one of Skopeo’s main documented features, including registry-to-registry copying. ([GitHub][2])

### If your local registry uses self-signed cert

```bash
skopeo copy --all \
  --dest-tls-verify=false \
  docker://quay.io/metallb/controller:v0.15.2 \
  docker://myregistry.local:5000/metallb/controller:v0.15.2
```

Use that only if your internal registry TLS is not trusted yet.

---

## 4) Install crane in WSL

The official project exposes crane as part of `go-containerregistry`, with commands like `crane auth login`, `crane digest`, `crane ls`, and copy operations. ([GitHub][4])

The easiest install path in WSL is usually via Go:

```bash
sudo apt update
sudo apt install -y golang-go
go install github.com/google/go-containerregistry/cmd/crane@latest
```

Then add Go bin to PATH if needed:

```bash
echo 'export PATH=$PATH:$HOME/go/bin' >> ~/.bashrc
source ~/.bashrc
```

Check:

```bash
crane version
```

---

## 5) Basic crane usage

### Login

```bash
crane auth login myregistry.local:5000
```

The official crane auth docs list `crane auth login`, `logout`, `get`, and `token`. ([GitHub][4])

### Copy image directly registry to registry

```bash
crane cp \
  registry.k8s.io/external-dns/external-dns:v0.15.0 \
  myregistry.local:5000/external-dns/external-dns:v0.15.0
```

For MetalLB:

```bash
crane cp \
  quay.io/metallb/controller:v0.15.2 \
  myregistry.local:5000/metallb/controller:v0.15.2

crane cp \
  quay.io/metallb/speaker:v0.15.2 \
  myregistry.local:5000/metallb/speaker:v0.15.2
```

For Emissary:

```bash
crane cp \
  docker.io/emissaryingress/emissary:3.10.2 \
  myregistry.local:5000/emissaryingress/emissary:3.10.2
```

The project docs describe `crane cp` as remote image to remote registry copy. ([GitHub][3])

### Check digest

```bash
crane digest quay.io/metallb/controller:v0.15.2
```

`crane digest` is an official documented command. ([GitHub][5])

---

## 6) Which is easier?

For you:

* **crane** = easier syntax
* **skopeo** = better for serious mirroring workflows

Examples side by side:

### crane

```bash
crane cp quay.io/metallb/controller:v0.15.2 myregistry.local:5000/metallb/controller:v0.15.2
```

### skopeo

```bash
skopeo copy --all docker://quay.io/metallb/controller:v0.15.2 docker://myregistry.local:5000/metallb/controller:v0.15.2
```

---

## 7) Practical flow for Helm charts

Your real workflow should be:

1. Render Helm chart
2. Extract image names
3. Mirror each image to local registry
4. Update Helm values to point to local registry

Example image extraction:

```bash
helm template externaldns external-dns/external-dns > externaldns.yaml
grep 'image:' externaldns.yaml | awk '{print $2}' | sort -u
```

Same idea for MetalLB and Emissary.

Then mirror each result with `skopeo copy` or `crane cp`.

---

## 8) WSL caveats

Yes, WSL works well, but keep these in mind:

* Best to use **WSL2**, not WSL1. Microsoft says new installs use WSL2 by default. ([Microsoft Learn][1])
* Your WSL instance must have network access to:

  * source registries like `quay.io`, `registry.k8s.io`, `docker.io`
  * your local registry
* If your local registry uses internal DNS, make sure WSL can resolve it
* If your local registry is using self-signed TLS, you may need:

  * trusted CA inside WSL, or
  * temporary insecure flags for testing only

---

## 9) My recommendation for your environment

Since you are doing **local kube installer / local repo / likely semi-airgapped infra**:

Use **skopeo** first.

Best starter pattern:

```bash
skopeo login myregistry.local:5000

skopeo copy --all \
  docker://registry.k8s.io/external-dns/external-dns:v0.15.0 \
  docker://myregistry.local:5000/external-dns/external-dns:v0.15.0
```

Then repeat for the rest.

---

## 10) Simple answer

Yes, **you can absolutely use WSL** for this, and it is a good choice.
If you want the easiest command style, use **crane**.
If you want the better image-mirroring tool for infra work, use **skopeo**. ([GitHub][2])

I can give you next a ready-made **WSL script** that will:

* read all images from ExternalDNS, MetalLB, and Emissary Helm charts
* mirror them to your local registry
* generate a `values-local.yaml` for each chart.

[1]: https://learn.microsoft.com/en-us/windows/wsl/install?utm_source=chatgpt.com "How to install Linux on Windows with WSL"
[2]: https://github.com/containers/skopeo "GitHub - containers/skopeo: Work with remote images registries - retrieving information, images, signing content · GitHub"
[3]: https://github.com/google/go-containerregistry?utm_source=chatgpt.com "google/go-containerregistry: Go library and CLIs ..."
[4]: https://github.com/google/go-containerregistry/blob/main/cmd/crane/doc/crane_auth.md "go-containerregistry/cmd/crane/doc/crane_auth.md at main · google/go-containerregistry · GitHub"
[5]: https://github.com/google/go-containerregistry/blob/main/cmd/crane/doc/crane_digest.md?utm_source=chatgpt.com "go-containerregistry/cmd/crane/doc/crane_digest.md at main"



✅ YES — very good thinking.
This is EXACTLY how infra engineers test **airgap mirroring flow**.

You can create a **temporary local registry container** then test:

```
public registry → skopeo → temporary registry → kubernetes pull
```

This is the correct lab simulation 👍

Let’s do this clean.

---

# ⭐ Step 1 — Run temporary registry (Docker)

In your WSL (Ubuntu):

```bash
docker run -d \
  -p 5000:5000 \
  --restart=always \
  --name temp-registry \
  registry:2
```

Check:

```bash
docker ps
```

You should see:

```
0.0.0.0:5000->5000/tcp
```

---

# ⭐ Step 2 — Test registry is reachable

Open browser (Windows):

```
http://localhost:5000/v2/
```

Expected:

```
{}
```

✅ means registry working.

---

# ⭐ Step 3 — Now test skopeo copy

VERY IMPORTANT

Since this registry has:

* no TLS
* no auth

You must use:

```
--dest-tls-verify=false
```

So:

```bash
skopeo copy --all \
  docker://registry.k8s.io/external-dns/external-dns:v0.15.0 \
  docker://localhost:5000/external-dns/external-dns:v0.15.0 \
  --dest-tls-verify=false
```

---

# ⭐ Step 4 — Verify image exists

List catalog:

```bash
curl http://localhost:5000/v2/_catalog
```

Expected:

```
{"repositories":["external-dns/external-dns"]}
```

Then:

```bash
curl http://localhost:5000/v2/external-dns/external-dns/tags/list
```

---

# ⭐ Step 5 — Try pulling via Docker

```bash
docker pull localhost:5000/external-dns/external-dns:v0.15.0
```

If works → registry + mirroring flow confirmed.

---

# ⭐ ⭐ ⭐ VERY IMPORTANT (WSL Networking Reality)

Sometimes WSL cannot access Windows localhost registry.

If that happens:

Use:

```
host.docker.internal:5000
```

Example:

```bash
skopeo copy --all \
 docker://registry.k8s.io/external-dns/external-dns:v0.15.0 \
 docker://host.docker.internal:5000/external-dns/external-dns:v0.15.0 \
 --dest-tls-verify=false
```

---

# ⭐ ⭐ ⭐ EVEN BETTER TEST (simulate real infra)

Run registry with custom name:

```bash
docker run -d \
 -p 5000:5000 \
 --name harbor-test \
 registry:2
```

Then add fake DNS in WSL:

```
sudo nano /etc/hosts
```

Add:

```
127.0.0.1 myregistry.local
```

Now test REAL command:

```bash
skopeo copy --all \
 docker://registry.k8s.io/external-dns/external-dns:v0.15.0 \
 docker://myregistry.local:5000/external-dns/external-dns:v0.15.0 \
 --dest-tls-verify=false
```

Now your testing is already **enterprise-style simulation**.

---

# ⭐ Step 6 — If you want to test Kubernetes pull

Create secret:

```bash
kubectl create secret docker-registry regcred \
  --docker-server=myregistry.local:5000 \
  --docker-username=dummy \
  --docker-password=dummy
```

Then pod:

```yaml
image: myregistry.local:5000/external-dns/external-dns:v0.15.0
imagePullPolicy: Always
```

---

# ⭐ ⭐ ⭐ Next Level (VERY IMPORTANT for YOU)

Since you are building:

* local kube installer
* airgap repo
* helm automation

You should actually build:

## 🔥 "local mirror registry bootstrap"

Like:

```
start registry
mirror all helm images
export registry storage
ship to production
```

This is how banks / telco / gov infra do.

---

# ⭐ If you want next

I can now give you:

✅ FULL automation script

```
mirror-helm-images.sh
```

It will:

* spin temporary registry
* render externaldns / metallb / emissary
* auto detect images
* mirror via skopeo
* generate values-local.yaml
* test pull

SUPER powerful for your kubernetes lab + prod installer.


✅ YES — you are now **very close to correct air-gap / local-repo Helm deployment 🙂**

If your temporary registry is reachable at:

```
http://192.168.1.30:5000
```

and images are successfully mirrored there using `skopeo` or `crane`…

👉 Then YES — you can now change the image references in:

* ExternalDNS
* Emissary Ingress
* MetalLB

to use this registry.

---

# ⭐ First VERY IMPORTANT check

Open:

```
http://192.168.1.30:5000/v2/_catalog
```

If you see:

```
{
 "repositories": [
   "external-dns/external-dns",
   "metallb/controller",
   "metallb/speaker",
   "emissary/emissary"
 ]
}
```

✅ GOOD
means registry ready.

---

# ⭐ Example — ExternalDNS Helm values change

Default image usually:

```
registry.k8s.io/external-dns/external-dns:v0.15.0
```

Change to:

```yaml
image:
  registry: 192.168.1.30:5000
  repository: external-dns/external-dns
  tag: v0.15.0
```

Then install:

```
helm upgrade --install externaldns external-dns/external-dns \
 -n dns \
 -f values-local.yaml
```

---

# ⭐ Example — MetalLB values

MetalLB has **two images**

* controller
* speaker

So:

```yaml
controller:
  image:
    repository: 192.168.1.30:5000/metallb/controller
    tag: v0.15.2

speaker:
  image:
    repository: 192.168.1.30:5000/metallb/speaker
    tag: v0.15.2
```

---

# ⭐ Example — Emissary

```yaml
image:
  repository: 192.168.1.30:5000/emissary/emissary
  tag: 3.10.2
```

---

# ⭐ VERY VERY IMPORTANT (Most people forget this)

Because your registry is:

* HTTP
* insecure
* no TLS

You MUST configure Kubernetes runtime.

Otherwise you will get:

```
ImagePullBackOff
x509 / http: server gave HTTP response to HTTPS client
```

---

# ⭐ If using containerd (most Kubernetes / Kubespray)

Edit:

```
/etc/containerd/config.toml
```

Add:

```toml
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.1.30:5000"]
  endpoint = ["http://192.168.1.30:5000"]

[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.30:5000".tls]
  insecure_skip_verify = true
```

Then:

```
systemctl restart containerd
```

---

# ⭐ Test Kubernetes Pull FIRST (recommended)

Before Helm install:

Create quick test pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-registry
spec:
  containers:
  - name: test
    image: 192.168.1.30:5000/external-dns/external-dns:v0.15.0
```

If pod runs → PERFECT 🙂

---

# ⭐ Enterprise advice (very important for your project)

Right now you are using:

```
registry:2 temporary
```

Good for testing.

But for REAL infra:

You should move to:

* Harbor
* Nexus
* GitLab Registry

Because they provide:

* UI
* image scan
* RBAC
* replication
* retention
* immutable tags
* TLS

---

# ⭐ BIG TIP for your Kubernetes local installer

Instead of editing every Helm chart manually…

You can define:

```
global.imageRegistry = 192.168.1.30:5000
```

Some charts support this 🙂

---

# ⭐ Summary

YES ✅
You can now:

* mirror images using skopeo
* store in `192.168.1.30:5000`
* change Helm values to use that registry
* configure container runtime insecure registry
* deploy normally

---

If you want — next I can give you something VERY POWERFUL:

🔥 **Full workflow:**

```
helm chart → auto detect images → mirror → rewrite values.yaml → install
```

One script only.

This is what serious platform teams build 👍


✅ Yes 👍 — `_catalog` only shows **repository names**, NOT tags / versions / metadata.

That endpoint:

```
http://192.168.1.30:5000/v2/_catalog
```

means only:

> “What image repos exist in this registry?”

To see **versions (tags)** and **other info**, you must query deeper registry API endpoints.

Let’s go infra-engineer style.

---

# ⭐ 1 — List tags (THIS is what you want)

If `_catalog` shows:

```
external-dns/external-dns
```

Then query:

```
http://192.168.1.30:5000/v2/external-dns/external-dns/tags/list
```

Example response:

```json
{
  "name": "external-dns/external-dns",
  "tags": [
    "v0.15.0",
    "v0.14.2"
  ]
}
```

✅ These are your **versions**

---

# ⭐ 2 — Using curl (recommended)

```bash
curl http://192.168.1.30:5000/v2/external-dns/external-dns/tags/list
```

For MetalLB controller:

```bash
curl http://192.168.1.30:5000/v2/metallb/controller/tags/list
```

---

# ⭐ 3 — See FULL image metadata (very powerful)

Now we go deeper — registry manifest.

```bash
curl -s \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  http://192.168.1.30:5000/v2/external-dns/external-dns/manifests/v0.15.0 | jq
```

You will see:

* digest
* layers
* architecture
* OS
* size

This is **real image info**.

---

# ⭐ 4 — SUPER NICE WAY (Use skopeo inspect)

Since you already use skopeo → BEST tool 🙂

```bash
skopeo inspect --tls-verify=false \
 docker://192.168.1.30:5000/external-dns/external-dns:v0.15.0
```

Output example:

```
Name
Digest
Created
Architecture
Os
Layers
Env
Labels
```

This is MUCH BETTER than raw registry API.

---

# ⭐ 5 — List ALL images + tags automatically

Infra trick 🙂

```bash
for repo in $(curl -s http://192.168.1.30:5000/v2/_catalog | jq -r '.repositories[]'); do
  echo "===== $repo ====="
  curl -s http://192.168.1.30:5000/v2/$repo/tags/list | jq
done
```

This will show ALL versions in registry.

---

# ⭐ 6 — If you want UI (recommended later)

Because `registry:2` has:

❌ no UI
❌ no search
❌ no tag browser

You can run temporary UI:

## 🔥 registry UI container

```bash
docker run -d \
 -p 8080:80 \
 -e REGISTRY_URL=http://192.168.1.30:5000 \
 joxit/docker-registry-ui:latest
```

Then open:

```
http://192.168.1.30:8080
```

Now you can:

✅ browse repos
✅ browse tags
✅ delete images

VERY useful lab tool.

---

# ⭐ 7 — Enterprise Reality

Real setups use:

* Harbor → best
* Nexus → good
* GitLab → good

Because they show:

* tag history
* vulnerabilities
* size
* pull count
* retention

---

# ⭐ VERY IMPORTANT TIP FOR YOU

Since you are building **local kube installer**…

You should also check:

```
digest consistency
```

Example:

```bash
skopeo inspect docker://registry.k8s.io/external-dns/external-dns:v0.15.0 | jq .Digest
skopeo inspect --tls-verify=false docker://192.168.1.30:5000/external-dns/external-dns:v0.15.0 | jq .Digest
```

They must be SAME.

This confirms:

✅ mirror success
✅ no corruption
✅ safe for airgap install

---

# ⭐ If you want next (VERY VERY powerful)

I can give you:

🔥 script:

```
registry-audit.sh
```

It will:

* list all repos
* list all tags
* show size
* show digest
* compare with public registry
* generate report

Very useful for platform teams 👍


Yes. The usual path is:

1. create a certificate
2. run the registry with TLS enabled
3. make your Docker/containerd clients trust that certificate
4. then use `https://...` instead of `http://...`

The registry supports TLS through its config, and Docker treats a private registry as “secure” when it uses TLS and the CA certificate is trusted by the client. ([distribution.github.io][1])

For your lab, the fastest good setup is a **self-signed CA + server cert** for `192.168.1.30` or, better, for a DNS name like `myregistry.local`. A DNS name is cleaner long-term because clients often expect certificates to match the registry hostname exactly. Docker’s docs also describe trusting the CA on clients by placing it in the registry certs directory. ([Docker Documentation][2])

## Recommended approach

Use a hostname such as `myregistry.local` mapped to `192.168.1.30`, then issue a cert for that name. After that, run the registry with TLS.

### 1) Add a hostname on the machines that will use the registry

On Linux or WSL clients:

```bash
echo "192.168.1.30 myregistry.local" | sudo tee -a /etc/hosts
```

On Windows, add the same mapping in the hosts file.

Then use:

```text
https://myregistry.local:5000
```

### 2) Generate certs

On the registry host, create a small OpenSSL config so the cert includes SANs:

```bash
mkdir -p ~/registry-certs
cd ~/registry-certs

cat > openssl.cnf <<'EOF'
[ req ]
default_bits       = 4096
prompt             = no
default_md         = sha256
x509_extensions    = v3_ca
distinguished_name = dn

[ dn ]
CN = My Local Registry CA

[ v3_ca ]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF
```

Create a local CA:

```bash
openssl req -x509 -new -nodes -days 3650 \
  -keyout ca.key -out ca.crt \
  -config openssl.cnf
```

Now create the server cert config:

```bash
cat > server.cnf <<'EOF'
[ req ]
default_bits       = 4096
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[ dn ]
CN = myregistry.local

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = myregistry.local
IP.1  = 192.168.1.30
EOF
```

Create key and CSR:

```bash
openssl req -new -nodes \
  -keyout registry.key \
  -out registry.csr \
  -config server.cnf
```

Sign it with your CA:

```bash
openssl x509 -req -days 825 \
  -in registry.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out registry.crt \
  -extensions req_ext -extfile server.cnf
```

That gives you:

* `ca.crt`
* `registry.crt`
* `registry.key`

### 3) Run the registry with TLS

The CNCF Distribution registry supports TLS settings in its configuration and can also be run in Docker. ([distribution.github.io][1])

Fastest container run:

```bash
docker rm -f temp-registry 2>/dev/null || true

docker run -d \
  --name temp-registry \
  -p 5000:5000 \
  -v "$PWD/registry.crt:/certs/registry.crt:ro" \
  -v "$PWD/registry.key:/certs/registry.key:ro" \
  -e REGISTRY_HTTP_ADDR=0.0.0.0:5000 \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/registry.key \
  registry:2
```

Now test:

```bash
curl -v https://myregistry.local:5000/v2/ --cacert ca.crt
```

If it works, you should get a successful TLS connection and the `/v2/` response.

### 4) Trust the CA on clients

Docker documents that a secure private registry uses TLS and that the CA can be placed under `/etc/docker/certs.d/<registry>/ca.crt` on Linux; Docker Desktop also incorporates trusted host certificates. ([Docker Documentation][3])

For Docker on Linux or WSL:

```bash
sudo mkdir -p /etc/docker/certs.d/myregistry.local:5000
sudo cp ca.crt /etc/docker/certs.d/myregistry.local:5000/ca.crt
sudo systemctl restart docker
```

For Docker Desktop on Windows, importing the CA into the Windows trusted root store is commonly enough because Docker Desktop builds its trust bundle from host-trusted CAs. ([Docker Documentation][4])

### 5) Push or mirror using HTTPS

Now your `skopeo` command becomes:

```bash
skopeo copy --all \
  docker://registry.k8s.io/external-dns/external-dns:v0.15.0 \
  docker://myregistry.local:5000/external-dns/external-dns:v0.15.0
```

No `--dest-tls-verify=false` needed once the CA is trusted.

### 6) Update Helm values

Then point your charts to:

```yaml
image:
  registry: myregistry.local:5000
  repository: external-dns/external-dns
  tag: v0.15.0
```

and similarly for Emissary and MetalLB.

## For Kubernetes nodes

Your cluster nodes also need to trust the CA. If you use containerd, place the CA where containerd expects it or configure the registry host with the trusted cert. The exact file path depends on distro and containerd setup, but the key idea is the same: the node runtime must trust the registry certificate before pulls succeed. Docker’s secure-registry guidance is the same principle: TLS plus trusted CA. ([Docker Documentation][3])

## If you want the simplest test first

You can keep your current plain HTTP registry for quick testing, but the registry project explicitly notes that HTTP or self-signed setups require extra client configuration and come with trade-offs; they recommend using TLS from a known CA when possible. ([distribution.github.io][5])

## Best practical advice for your setup

For your homelab / local installer:

* use `myregistry.local:5000` instead of raw IP
* create your own CA once
* issue a registry cert from that CA
* trust `ca.crt` on WSL, Windows, and all Kubernetes nodes
* then mirror images and update Helm values

That gives you a much more production-like flow than `http://192.168.1.30:5000`. ([Docker Documentation][2])

I can give you a ready-to-run `docker-compose.yml` plus OpenSSL script for `myregistry.local:5000` next.

[1]: https://distribution.github.io/distribution/about/configuration/?utm_source=chatgpt.com "Configuring a registry | CNCF Distribution"
[2]: https://docs.docker.com/engine/security/certificates/?utm_source=chatgpt.com "Verify repository client with certificates"
[3]: https://docs.docker.com/reference/cli/dockerd/?utm_source=chatgpt.com "dockerd"
[4]: https://docs.docker.com/desktop/troubleshoot-and-support/faqs/windowsfaqs/?utm_source=chatgpt.com "FAQs for Docker Desktop for Windows"
[5]: https://distribution.github.io/distribution/about/insecure/?utm_source=chatgpt.com "Test an insecure registry | CNCF Distribution"

//////////////
Yes — here’s a **practical Skopeo cheatsheet** for your exact job:

**public registry → local HTTPS registry → verify → use in Helm/Kubernetes**

Skopeo can inspect remote images without pulling, copy images between registries, sync repositories for air-gapped use, and work without a daemon/root for most operations. ([GitHub][1])

---

## Skopeo basics

General format:

```bash
skopeo [global options] command [command options]
```

Common image transport you’ll use:

```bash
docker://REGISTRY/REPO:TAG
```

Skopeo’s main commands for your workflow are `inspect`, `copy`, `list-tags`, `login`, `delete`, and `sync`. ([GitHub][1])

---

## 1) Install

Ubuntu / WSL:

```bash
sudo apt update
sudo apt install -y skopeo jq
skopeo --version
```

Ubuntu provides `skopeo` as a package, and the man page documents its CLI behavior. ([Ubuntu Manpages][2])

---

## 2) Inspect a public image

Check image info without pulling:

```bash
skopeo inspect docker://registry.k8s.io/external-dns/external-dns:v0.15.0
```

Useful fields include digest, architecture, OS, layers, labels, and env metadata. `inspect` is specifically intended to show image properties without pulling. ([GitHub][1])

Pretty output:

```bash
skopeo inspect docker://registry.k8s.io/external-dns/external-dns:v0.15.0 | jq
```

Digest only:

```bash
skopeo inspect docker://registry.k8s.io/external-dns/external-dns:v0.15.0 | jq -r .Digest
```

---

## 3) List tags / versions

Show available tags in a repo:

```bash
skopeo list-tags docker://registry.k8s.io/external-dns/external-dns
```

Pretty:

```bash
skopeo list-tags docker://registry.k8s.io/external-dns/external-dns | jq
```

This is the easiest way to discover versions before mirroring. `list-tags` is a documented subcommand in Skopeo’s CLI. ([Ubuntu Manpages][2])

---

## 4) Login to your private registry

If your registry needs auth:

```bash
skopeo login myregistry.local:5000
```

Or:

```bash
skopeo login 192.168.1.30:5000
```

Skopeo supports passing credentials and certificates when required by the repository. ([GitHub][1])

---

## 5) Copy image: public → private registry

### Basic copy

```bash
skopeo copy \
  docker://registry.k8s.io/external-dns/external-dns:v0.15.0 \
  docker://192.168.1.30:5000/external-dns:v0.15.0
```

### Copy all architectures / manifest list

```bash
skopeo copy --all \
  docker://registry.k8s.io/external-dns/external-dns:v0.15.0 \
  docker://192.168.1.30:5000/external-dns:v0.15.0
```

`copy` is the core Skopeo feature for registry-to-registry mirroring, and `--all` is important when you want the full multi-arch image set instead of just one platform. ([GitHub][1])

### If your private registry cert is not trusted yet

```bash
skopeo copy --all \
  --dest-tls-verify=false \
  docker://registry.k8s.io/external-dns/external-dns:v0.15.0 \
  docker://192.168.1.30:5000/external-dns:v0.15.0
```

### If source also has broken/untrusted TLS

```bash
skopeo copy --all \
  --src-tls-verify=false \
  --dest-tls-verify=false \
  docker://SOURCE/REPO:TAG \
  docker://DEST/REPO:TAG
```

---

## 6) Inspect your private registry image after copy

```bash
skopeo inspect --tls-verify=false \
  docker://192.168.1.30:5000/external-dns:v0.15.0
```

If your CA is already trusted:

```bash
skopeo inspect docker://192.168.1.30:5000/external-dns:v0.15.0
```

This is the best verification step after mirroring. ([GitHub][1])

---

## 7) Compare source and destination digest

Source:

```bash
skopeo inspect docker://registry.k8s.io/external-dns/external-dns:v0.15.0 | jq -r .Digest
```

Destination:

```bash
skopeo inspect --tls-verify=false docker://192.168.1.30:5000/external-dns:v0.15.0 | jq -r .Digest
```

If the digests match, your mirror is correct. Skopeo inspect exposes the digest specifically for this sort of verification. ([Ubuntu Manpages][2])

---

## 8) Copy to simpler repo names

For homelab/local installer work, I recommend flatter names.

### ExternalDNS

```bash
skopeo copy --all \
  --dest-tls-verify=false \
  docker://registry.k8s.io/external-dns/external-dns:v0.15.0 \
  docker://192.168.1.30:5000/external-dns:v0.15.0
```

### MetalLB

```bash
skopeo copy --all \
  --dest-tls-verify=false \
  docker://quay.io/metallb/controller:v0.15.2 \
  docker://192.168.1.30:5000/metallb-controller:v0.15.2

skopeo copy --all \
  --dest-tls-verify=false \
  docker://quay.io/metallb/speaker:v0.15.2 \
  docker://192.168.1.30:5000/metallb-speaker:v0.15.2
```

### Emissary

```bash
skopeo copy --all \
  --dest-tls-verify=false \
  docker://docker.io/emissaryingress/emissary:3.10.2 \
  docker://192.168.1.30:5000/emissary:v3.10.2
```

---

## 9) Delete an image tag from your private registry

```bash
skopeo delete --tls-verify=false \
  docker://192.168.1.30:5000/external-dns:v0.15.0
```

`delete` is one of the documented image-repository operations in Skopeo. ([GitHub][1])

---

## 10) Sync many images for air-gapped use

Skopeo supports `sync` specifically for syncing an external repository into an internal registry for air-gapped deployments. ([GitHub][1])

Example idea:

```bash
skopeo sync --all \
  --src docker \
  --dest docker \
  docker.io/library/alpine \
  192.168.1.30:5000/mirror
```

That said, for your current Helm-image job, `copy` is usually easier and more predictable than `sync`.

---

## 11) Most useful flags

```bash
--all
```

Copy all images in a manifest list / multi-arch image.

```bash
--src-tls-verify=false
```

Skip TLS verification for source registry.

```bash
--dest-tls-verify=false
```

Skip TLS verification for destination registry.

```bash
--src-creds user:pass
```

Credentials for source registry.

```bash
--dest-creds user:pass
```

Credentials for destination registry.

```bash
--format oci
```

Convert output manifest format when applicable.

These options are part of Skopeo’s documented copy behavior and shared command structure. ([Ubuntu Manpages][2])

---

## 12) Your exact workflow cheatsheet

### Find tag

```bash
skopeo list-tags docker://registry.k8s.io/external-dns/external-dns | jq
```

### Inspect source

```bash
skopeo inspect docker://registry.k8s.io/external-dns/external-dns:v0.15.0 | jq
```

### Copy to local registry

```bash
skopeo copy --all \
  --dest-tls-verify=false \
  docker://registry.k8s.io/external-dns/external-dns:v0.15.0 \
  docker://192.168.1.30:5000/external-dns:v0.15.0
```

### Verify copied image

```bash
skopeo inspect --tls-verify=false \
  docker://192.168.1.30:5000/external-dns:v0.15.0 | jq
```

### Compare digest

```bash
skopeo inspect docker://registry.k8s.io/external-dns/external-dns:v0.15.0 | jq -r .Digest
skopeo inspect --tls-verify=false docker://192.168.1.30:5000/external-dns:v0.15.0 | jq -r .Digest
```

---

## 13) Helm mapping examples

### ExternalDNS

```yaml
image:
  registry: 192.168.1.30:5000
  repository: external-dns
  tag: v0.15.0
```

### MetalLB

```yaml
controller:
  image:
    repository: 192.168.1.30:5000/metallb-controller
    tag: v0.15.2

speaker:
  image:
    repository: 192.168.1.30:5000/metallb-speaker
    tag: v0.15.2
```

### Emissary

```yaml
image:
  repository: 192.168.1.30:5000/emissary
  tag: v3.10.2
```

---

## 14) Common errors and meaning

### `NAME_UNKNOWN`

Wrong repo path, or repo does not exist in registry.

### `manifest unknown`

Repo exists, but that exact tag/digest does not exist.

### `x509: certificate signed by unknown authority`

Your client/node does not trust the registry CA.

### `certificate is valid for X, not Y`

Hostname/IP does not match cert SAN.

These behaviors follow standard registry API naming/tag resolution and TLS trust expectations for private registries. ([GitHub][1])

---

## 15) My recommendation for your setup

For your lab/local installer:

* use **flat image names**
* use `skopeo copy --all`
* verify with `skopeo inspect`
* compare digests
* only use `--dest-tls-verify=false` temporarily
* once stable, install your CA on Docker/containerd nodes

I can turn this into a **copy-paste shell script cheatsheet** for ExternalDNS, MetalLB, and Emissary specifically.

[1]: https://github.com/containers/skopeo?utm_source=chatgpt.com "containers/skopeo: Work with remote images registries"
[2]: https://manpages.ubuntu.com/manpages/noble/man1/skopeo.1.html?utm_source=chatgpt.com "skopeo -- Command line utility used to interact with local ..."
