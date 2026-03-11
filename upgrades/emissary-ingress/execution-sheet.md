# ⭐ Emissary Helm Upgrade Execution Timeline (Run Sheet)

This is based on your path:

```
7.1.10 → 7.2.0 → 7.2.2 → 7.3.2 → 7.4.2 → 7.5.x → 8.x
```

---

## 🧭 Upgrade Execution Table

| Version Step       | Upgrade Command                                                                                                                         | Expected Pod Behavior                                 | Downtime Risk | Validation Commands                                                                         | Notes                    |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- | ------------- | ------------------------------------------------------------------------------------------- | ------------------------ |
| **7.1.10 → 7.2.0** | `helm upgrade my-emissary-ingress datawire/emissary-ingress -n ambassador --version 7.2.0 -f values.yaml --atomic --wait --timeout 10m` | Rolling restart (all Emissary pods restart)           | 🟡 Medium     | `kubectl get pods -n ambassador`<br>`kubectl logs deploy/my-emissary-ingress -n ambassador` | Must apply CRDs first    |
| **7.2.0 → 7.2.2**  | `helm upgrade ... --version 7.2.2 --reuse-values`                                                                                       | Fast rolling restart                                  | 🟢 Low        | `kubectl rollout status deploy/my-emissary-ingress -n ambassador`                           | Mostly image bump        |
| **7.2.2 → 7.3.2**  | `helm upgrade ... --version 7.3.2 --reuse-values`                                                                                       | Rolling restart                                       | 🟢 Low        | Test ingress route / DNS                                                                    | Minor template change    |
| **7.3.2 → 7.4.2**  | `helm upgrade ... --version 7.4.2 --reuse-values`                                                                                       | Rolling restart                                       | 🟢 Low        | `kubectl get svc -n ambassador`                                                             | Listener/service cleanup |
| **7.4.2 → 7.5.x**  | `helm upgrade ... --version 7.5.x --reuse-values`                                                                                       | Rolling restart                                       | 🟡 Medium     | Metrics + routing validation                                                                | Review diff first        |
| **7.x → 8.0.0**    | `helm upgrade ... --version 8.0.0 -f values.yaml --atomic --wait`                                                                       | Full controller restart + possible CRD reconciliation | 🔴 High       | Test TLS / wildcard / DNS / routing                                                         | Major chart redesign     |
| **8.0.x → 8.12.x** | `helm upgrade ... --version 8.12.2 --reuse-values`                                                                                      | Rolling restart                                       | 🟡 Medium     | Check listeners + metrics                                                                   | Feature accumulation     |

---

# ⭐ Maintenance Window Flow (REAL)

During actual upgrade window:

### Step 1 — Pre-check

```bash
kubectl get pods -n ambassador
kubectl get svc -n ambassador
kubectl get ingress -A
```

---

### Step 2 — Run Upgrade

Example:

```bash
helm upgrade my-emissary-ingress datawire/emissary-ingress \
-n ambassador \
--version 7.3.2 \
--reuse-values \
--atomic \
--wait \
--timeout 10m
```

---

### Step 3 — Watch Rollout

```bash
kubectl rollout status deploy/my-emissary-ingress -n ambassador
```

---

### Step 4 — Functional Validation (VERY IMPORTANT)

Test:

* wildcard domain
* HTTPS endpoint
* DNS resolution
* backend routing

Example:

```bash
curl -k https://your-domain
```

---

### Step 5 — Observability Validation

```bash
kubectl get servicemonitor -A
kubectl logs deploy/my-emissary-ingress -n ambassador
```

---

### Step 6 — Record Revision

```bash
helm history my-emissary-ingress -n ambassador
```

---

# ⭐ Downtime Reality

If replicaCount ≥ 2:

→ Almost **zero downtime** (rolling update)

If replicaCount = 1:

→ Short ingress interruption possible.

---

# ⭐ Golden Upgrade Command Template

Reuse-safe:

```bash
helm upgrade my-emissary-ingress datawire/emissary-ingress \
-n ambassador \
--version X \
--reuse-values \
--atomic --wait --timeout 10m
```

Controlled:

```bash
helm get values my-emissary-ingress -n ambassador -o yaml > values.yaml

kubectl apply -f emissary-crds.yaml

helm upgrade my-emissary-ingress datawire/emissary-ingress \
-n ambassador \
--version X \
-f values.yaml \
--atomic --wait --timeout 10m
```

---

# ⭐ What You Have Now

You now have:

✅ diff methodology
✅ reuse vs controlled logic
✅ upgrade matrix
✅ execution timeline
✅ validation checklist

This is already **enterprise-grade upgrade planning.**
