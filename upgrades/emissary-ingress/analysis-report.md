# 📄 Emissary Ingress Helm Upgrade Analysis Report

---

## 1. Objective

Upgrade **Emissary Ingress Helm chart** from legacy version to latest stable release in a controlled version-by-version manner to:

* obtain bug fixes and security improvements
* align with Kubernetes **v1.31 compatibility**
* reduce ingress routing risks
* avoid CRD lifecycle failures

---

## 2. Current Environment

| Parameter             | Value               |
| --------------------- | ------------------- |
| Cluster Version       | Kubernetes 1.31     |
| Namespace             | ambassador          |
| Release Name          | my-emissary-ingress |
| Current Chart Version | 7.1.10              |
| Current App Version   | 2.0.5               |
| Replica Count         | 3                   |
| Ingress Type          | Emissary Ingress    |

---

## 3. Target Upgrade Strategy

A **version stepping approach** will be used.

### Planned Upgrade Path

```
7.1.10
→ 7.2.0
→ 7.2.2
→ 7.3.2
→ 7.4.2
→ 7.5.x
→ 8.x
→ 8.12.x
```

This minimizes:

* CRD reconciliation risk
* RBAC permission drift
* listener routing regression

---

## 4. Helm Chart Diff Analysis Summary

| From   | To    | Diff Size  | Key Observations                                                    | Risk        |
| ------ | ----- | ---------- | ------------------------------------------------------------------- | ----------- |
| 7.1.10 | 7.2.0 | Medium     | CRD lifecycle removed from chart, RBAC refactor, API version update | Medium-High |
| 7.2.0  | 7.2.2 | Very Small | Image bump and minor fixes                                          | Low         |
| 7.2.2  | 7.3.0 | Small      | Template cleanup and helper refactor                                | Low         |
| 7.3.0  | 7.3.2 | Very Small | Bugfix release                                                      | Low         |
| 7.3.2  | 7.4.0 | Small      | Listener/service template adjustments                               | Low-Medium  |
| 7.4.0  | 7.4.2 | Very Small | Metadata/image updates                                              | Low         |
| 7.4.2  | 7.5.x | Medium     | Controller behavior improvements                                    | Medium      |
| 7.x    | 8.0.0 | Large      | Major chart redesign and Emissary 3.x adoption                      | High        |

---

## 5. Key Upgrade Findings

### 5.1 CRD Lifecycle Change (Critical)

Starting **7.2.0**, CRDs are no longer automatically installed or managed by Helm.

Action Required:

```
kubectl apply -f emissary-crds.yaml
```

Failure to do so may result in:

* controller startup failure
* invalid module/resolver objects

---

### 5.2 RBAC Model Refactor

* ClusterRole aggregation introduced
* RoleBinding structure changed

Impact:

* Possible permission scope changes
* Must validate controller logs post upgrade

---

### 5.3 API Version Adjustments

Example:

```
getambassador.io/v3alpha1 → v2
```

Impact:

* Existing CRD schema compatibility must be verified

---

### 5.4 Runtime Image Upgrades

Across minor versions:

```
Emissary 2.x → 3.x
```

Potential effects:

* listener validation logic changes
* metrics exposure changes
* routing behavior refinement

---

## 6. Upgrade Decision Matrix

| Version Step   | Reuse Values Safe | Controlled Upgrade Needed | Reason                    |
| -------------- | ----------------- | ------------------------- | ------------------------- |
| 7.1.10 → 7.2.0 | No                | Yes                       | CRD lifecycle removal     |
| 7.2.0 → 7.2.2  | Yes               | No                        | Minor image change        |
| 7.2.2 → 7.3.2  | Yes               | No                        | Template cosmetic change  |
| 7.3.2 → 7.4.2  | Yes               | No                        | Listener cleanup          |
| 7.4.2 → 7.5.x  | Review            | Possibly                  | Internal controller logic |
| 7.x → 8.0.0    | No                | Yes                       | Major redesign            |

---

## 7. Execution Plan

### 7.1 Backup Current State

```bash
helm get values my-emissary-ingress -n ambassador -o yaml > values-backup.yaml
helm get manifest my-emissary-ingress -n ambassador > manifest-backup.yaml
```

---

### 7.2 Apply CRDs (If Required)

```bash
kubectl apply -f emissary-crds.yaml
```

---

### 7.3 Perform Upgrade

Reuse-safe upgrade example:

```bash
helm upgrade my-emissary-ingress datawire/emissary-ingress \
-n ambassador \
--version 7.3.2 \
--reuse-values \
--atomic --wait --timeout 10m
```

Controlled upgrade example:

```bash
helm upgrade my-emissary-ingress datawire/emissary-ingress \
-n ambassador \
--version 7.2.0 \
-f values-backup.yaml \
--atomic --wait --timeout 10m
```

---

## 8. Validation Plan

| Component | Validation Method                                                 |
| --------- | ----------------------------------------------------------------- |
| Pods      | `kubectl rollout status deploy/my-emissary-ingress -n ambassador` |
| Routing   | curl ingress domain                                               |
| TLS       | Browser validation                                                |
| DNS       | external resolution test                                          |
| Metrics   | Prometheus target status                                          |

---

## 9. Rollback Strategy

```bash
helm history my-emissary-ingress -n ambassador
helm rollback my-emissary-ingress <revision>
```

Rollback should be possible due to:

* values backup
* manifest snapshot
* Helm revision history

---

## 10. Maintenance Window Timeline

| Time Offset | Activity                    |
| ----------- | --------------------------- |
| T-30m       | Backup values and manifests |
| T-20m       | Apply CRDs                  |
| T-10m       | Execute upgrade             |
| T           | Validate ingress traffic    |
| T+10m       | Observe logs and metrics    |

---

## 11. Risk Assessment

| Risk                     | Mitigation                     |
| ------------------------ | ------------------------------ |
| Ingress downtime         | Maintain replicaCount ≥ 2      |
| CRD mismatch             | Manual CRD application         |
| RBAC regression          | Log monitoring                 |
| Listener routing failure | Functional endpoint validation |

---

## 12. Supporting Artifacts

* Chart diff outputs
* Rendered manifest diff
* values backup file
* upgrade execution logs

---

# ✅ Conclusion

A **controlled, version-stepped upgrade** is recommended to safely transition Emissary Ingress from legacy chart versions to modern releases while maintaining ingress stability and minimizing routing disruption.

