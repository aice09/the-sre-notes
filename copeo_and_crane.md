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
