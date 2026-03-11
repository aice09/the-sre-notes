# ⭐ Emissary Helm Upgrade Decision Matrix

## 🧭 Version-by-Version Upgrade Guide

| From   | To     | Chart Diff Size     | Major Change Type                                             | Reuse Values Safe? | Extra Action                                  | Risk           |
| ------ | ------ | ------------------- | ------------------------------------------------------------- | ------------------ | --------------------------------------------- | -------------- |
| 7.1.10 | 7.2.0  | ⭐ Medium            | **CRD lifecycle change + RBAC refactor + API version change** | ❌ NO               | Apply `emissary-crds.yaml`, clean values.yaml | 🔴 Medium-High |
| 7.2.0  | 7.2.2  | ⭐ Very Small / None | Mostly image bump / minor fixes                               | ✅ YES              | Helm diff recommended                         | 🟢 Low         |
| 7.2.2  | 7.3.0  | ⭐ Small–Medium      | Image bump + minor template adjustments                       | ✅ Usually          | Helm diff + rendered diff                     | 🟡 Low         |
| 7.3.0  | 7.3.2  | ⭐ Very Small        | Bugfix release                                                | ✅ YES              | None normally                                 | 🟢 Low         |
| 7.3.2  | 7.4.0  | ⭐ Small             | Listener / lifecycle template cleanup                         | ⚠️ Review          | Template diff first                           | 🟡 Low–Medium  |
| 7.4.0  | 7.4.2  | ⭐ Very Small        | Image bump / metadata                                         | ✅ YES              | Safe reuse                                    | 🟢 Low         |
| 7.4.2  | 7.5.x  | ⭐ Medium            | Internal controller improvements                              | ⚠️ Review          | Render diff recommended                       | 🟡 Medium      |
| 7.x    | 8.0.0  | ⭐ LARGE             | **Major chart redesign + Emissary 3.x line**                  | ❌ NO               | Export values + full validation               | 🔴 HIGH        |
| 8.0.x  | 8.9.x  | ⭐ Medium            | Feature additions                                             | ⚠️ Review          | Helm diff required                            | 🟡 Medium      |
| 8.9.x  | 8.12.x | ⭐ Small             | Incremental improvements                                      | ✅ Usually          | Diff still recommended                        | 🟡 Low         |

---

# ⭐ Golden Rules Derived From This Matrix

## 🔴 ALWAYS Controlled Upgrade When

* CRDs change
* apiVersion change
* Major version jump (7 → 8)
* RBAC redesign
* selector change
* Service ports change

Command style:

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

## 🟢 Safe Reuse Upgrade When

* Only image tag changed
* Labels/helper refactor
* Minor bugfix release
* No CRD / RBAC / selector diff

Command style:

```bash
helm upgrade my-emissary-ingress datawire/emissary-ingress \
-n ambassador \
--version X \
--reuse-values \
--atomic --wait --timeout 10m
```

---

# ⭐ Upgrade Strategy Recommendation (REAL)

If your current cluster was:

```text
7.1.10
```

Best safe path:

```text
7.1.10
→ 7.2.0  (controlled)
→ 7.2.2  (reuse)
→ 7.3.2  (reuse)
→ 7.4.2  (reuse)
→ 7.5.x  (review)
→ 8.x    (controlled major)
```

This minimizes risk.

---

# ⭐ Senior-Level Tip (VERY Important)

You do NOT need to diff every micro version.

Instead:

* diff first version where **real change happened**
* skip trivial versions

Example:

If:

```text
7.2.0 == 7.2.2 (no diff)
```

Then focus on:

```text
7.2.2 → 7.3.0
```

Correct.


