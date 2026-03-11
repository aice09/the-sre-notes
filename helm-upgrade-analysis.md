# ⭐ Helm Upgrade Analysis Runbook Table

You can copy this template.

| Step | Task                               | Command                                                                                                                                                 | Purpose / Explanation                                    | Risk Level         |
| ---- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ------------------ |
| 1    | Identify current release version   | `helm list -n ambassador`                                                                                                                               | Confirms deployed chart + app version                    | 🟢 Low             |
| 2    | Backup current values              | `helm get values my-emissary-ingress -n ambassador -o yaml > values-backup.yaml`                                                                        | Needed for rollback / controlled upgrade                 | 🟢 Low             |
| 3    | Backup current manifest            | `helm get manifest my-emissary-ingress -n ambassador > manifest-backup.yaml`                                                                            | Snapshot of real deployed Kubernetes YAML                | 🟢 Low             |
| 4    | Pull chart versions to compare     | `helm pull datawire/emissary-ingress --version 7.2.2 --untar --untardir charts/7.2.2`                                                                   | Prepare chart source for diff analysis                   | 🟢 Low             |
| 5    | Perform chart diff                 | `diff -ur charts/7.2.2 charts/7.3.0 > diff.txt`                                                                                                         | Detect structural changes (CRD, RBAC, templates)         | 🟡 Medium          |
| 6    | Perform template-only diff         | `diff -ur charts/7.2.2/templates charts/7.3.0/templates > templates-diff.txt`                                                                           | Focus on Kubernetes resource changes                     | 🟡 Medium          |
| 7    | Perform values diff                | `diff -u charts/7.2.2/values.yaml charts/7.3.0/values.yaml`                                                                                             | Detect default config change affecting reuse-values      | 🟡 Medium          |
| 8    | Render manifest diff (BEST METHOD) | `helm template old charts/7.2.2 -f values.yaml > old.yaml`<br>`helm template new charts/7.3.0 -f values.yaml > new.yaml`<br>`diff -u old.yaml new.yaml` | Shows exact cluster impact before upgrade                | 🔴 High importance |
| 9    | Check CRD changes                  | `grep -i crd diff.txt`                                                                                                                                  | Detect if manual CRD apply is required                   | 🔴 High            |
| 10   | Check RBAC changes                 | `grep -i role diff.txt`                                                                                                                                 | Detect permission behavior change                        | 🟡 Medium          |
| 11   | Check selector / port changes      | `grep -i selector diff.txt`<br>`grep -i port diff.txt`                                                                                                  | Detect traffic routing risk                              | 🔴 High            |
| 12   | Check container runtime changes    | `grep -i image diff.txt`<br>`grep -i args diff.txt`                                                                                                     | Usually safe rolling upgrade                             | 🟢 Low             |
| 13   | Review upstream CHANGELOG          | *(read GitHub release notes)*                                                                                                                           | Detect runtime behavior change not visible in chart diff | 🔴 High            |
| 14   | Decide upgrade method              | reuse-values OR controlled upgrade                                                                                                                      | Prevent upgrade failure                                  | 🔴 High            |
| 15   | Apply CRDs (if required)           | `kubectl apply -f emissary-crds.yaml`                                                                                                                   | Required for CRD lifecycle changes                       | 🔴 High            |
| 16   | Perform dry run                    | `helm upgrade ... --dry-run`                                                                                                                            | Validate manifest before execution                       | 🟡 Medium          |
| 17   | Execute upgrade                    | `helm upgrade ... --atomic --wait --timeout 10m`                                                                                                        | Safe production upgrade execution                        | 🔴 High            |
| 18   | Verify rollout                     | `kubectl rollout status deploy/my-emissary-ingress -n ambassador`                                                                                       | Confirm successful controller restart                    | 🟢 Low             |
| 19   | Functional traffic validation      | curl / browser / DNS test                                                                                                                               | Ensure ingress routing still works                       | 🔴 High            |
| 20   | Record revision                    | `helm history my-emissary-ingress -n ambassador`                                                                                                        | Track upgrade audit trail                                | 🟢 Low             |

---

# ⭐ How You Use This Table

For every version jump:

Example:

```text
7.2.2 → 7.3.0
```

You go row by row.

This ensures:

✅ no blind upgrades
✅ no CRD surprises
✅ no traffic outage
✅ safe rollback

---

# ⭐ Real Mental Model

Your workflow becomes:

```text
Pull chart
→ diff chart
→ diff templates
→ diff rendered manifests
→ check changelog
→ decide reuse vs controlled
→ upgrade
→ validate traffic
```
