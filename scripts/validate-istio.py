#!/usr/bin/env python3
"""CI policy checks on committed manifests (runs in PR checks and in Jenkins)."""
import glob, sys, yaml
errors = []
def err(f, n, msg): errors.append(f"{f}: {n}: {msg}")
for f in sorted(glob.glob("istio/*.yaml") + glob.glob("k8s/*.yaml")):
    for d in yaml.safe_load_all(open(f)):
        if not d: continue
        kind, name = d.get("kind"), d.get("metadata", {}).get("name", "-")
        spec = d.get("spec", {})
        if kind == "VirtualService":
            for h in spec.get("http", []):
                if "timeout" not in h: err(f, name, "missing timeout")
                if "retries" not in h and not f.endswith("rollback-v1-only.yaml"): err(f, name, "missing retries")
                if "fault" in h: err(f, name, "fault injection must live in chaos/, not in deployable manifests")
                for r in h.get("route", []):
                    dest = r["destination"]
                    if dest.get("subset") == "v2" and r.get("weight", 100) > 25:
                        err(f, name, f"canary v2 weight {r.get('weight', 100)} > 25 (use scripts/promote.sh with the guard)")
        if kind == "DestinationRule" and name == "payment-service" and "outlierDetection" not in spec.get("trafficPolicy", {}):
            err(f, name, "payment-service needs outlierDetection (circuit breaker)")
        if kind == "PeerAuthentication" and d["metadata"].get("namespace") == "istio-system" and spec.get("mtls", {}).get("mode") != "STRICT":
            err(f, name, "mesh-wide mTLS must be STRICT")
        if kind in ("Deployment", "StatefulSet"):
            for c in spec["template"]["spec"]["containers"]:
                lim = c.get("resources", {}).get("limits", {})
                if "memory" not in lim or "cpu" not in lim: err(f, name, f"container {c['name']} lacks cpu/memory limits")
                if ":latest" in c["image"] or ":" not in c["image"]: err(f, name, f"image {c['image']} must have a pinned tag")
if errors:
    print("❌ policy violations:"); [print(" -", e) for e in errors]; sys.exit(1)
print("✅ manifests pass policy checks")
