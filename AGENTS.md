# AGENTS.md

## Repo Overview

`parasol` is a GitOps-managed Talos Linux homelab cluster. Infrastructure configuration lives alongside Kubernetes manifests in this repository. Changes pushed to `main` are reconciled by Flux running in-cluster.

## Cluster

- **OS**: Talos Linux v1.12.2
- **Kubernetes**: v1.35.0
- **Topology**: Single node (`node-01`, `10.128.1.140`), control plane with `allowSchedulingOnControlPlanes: true`
- **Endpoint**: `https://10.128.1.140:6443`
- **Install disk**: `/dev/nvme0n1`

### Talos Extensions

- `siderolabs/i915` — Intel integrated GPU
- `siderolabs/intel-ice-firmware` — Intel network adapter firmware
- `siderolabs/intel-ucode` — Intel CPU microcode updates
- `siderolabs/iscsi-tools` — iSCSI initiator support
- `siderolabs/thunderbolt` — Thunderbolt device support

### Networking

- CNI: **none** (Talos-managed CNI disabled; Cilium handles this)
- kube-proxy: **disabled** (Cilium eBPF replaces it)
- BGP: enabled via Cilium
- kubePrism: enabled on port `7445`
- hostDNS: enabled, `forwardKubeDNSToHost: false`

## Repository Layout

```
.
├── cluster/              # Live cluster state (Flux-reconciled)
├── nodes/                # Talhelper config for node/cluster definition
├── .sops.yaml            # SOPS rules for secret encryption
├── diff.sh               # HelmRelease diff tool (used in PR review)
└── .github/              # GitHub Actions workflows
```

### Cluster Directory Structure

The `cluster` Flux Kustomization applies the top-level `kustomization.yaml`, which distributes per-app Flux Kustomization objects. Each app then reconciles independently. Apps that depend on CRDs from a HelmRelease (e.g. cert-manager) split into an `app/` KS with a healthCheck and a `config/` KS with `dependsOn`.

```
cluster/
├── kustomization.yaml             # References each app's ks.yaml directly
├── cert-manager/
│   ├── ks.yaml                    # Flux KSes: cert-manager → app/, cert-manager-config → config/ (dependsOn cert-manager)
│   ├── app/                       # namespace.yaml, secret.sops.yaml, helmrelease.yaml, kustomization.yaml
│   └── config/                    # ClusterIssuer, Certificate (CRD-dependent resources)
├── external-dns/                  # Same pattern; has secret.sops.yaml + postBuild; no config/ split
│   ├── ks.yaml
│   └── app/                       # namespace.yaml, secret.sops.yaml, helmrelease.yaml, kustomization.yaml
├── flux-system/
│   ├── cluster/                   # cluster ConfigMap + Secret (postBuild substituteFrom) + ks.yaml (root cluster KS)
│   ├── gitrepositories/           # Git sources
│   ├── helmrepositories/          # One HelmRepository per chart source
│   └── ocirepositories/           # OCI chart sources
├── kube-system/
│   ├── kustomization.yaml         # References one subdir (local-path-provisioner/) + inline KS yaml files
│   ├── cilium-ks.yaml             # Flux KS → ./cluster/kube-system/cilium
│   ├── cilium/                    # helmrelease.yaml, kustomization.yaml (no namespace.yaml)
│   ├── cilium-bgp-ks.yaml
│   ├── cilium-bgp/                # CiliumBGPClusterConfig, CiliumBGPPeerConfig, CiliumBGPAdvertisement, CiliumLoadBalancerIPPool
│   ├── gateway-api-ks.yaml        # Points at gateway-api GitRepository, not this repo
│   ├── multus-ks.yaml
│   ├── multus/
│   └── local-path-provisioner/    # No separate -ks.yaml; HelmRelease applied inline by cluster KS (no independent Flux Kustomization object)
└── scrypted/
    ├── ks.yaml
    └── app/                       # namespace.yaml, helmrelease.yaml, kustomization.yaml
```

The `cluster` Flux Kustomization (defined in `cluster/flux-system/cluster/ks.yaml`) applies the top-level `kustomization.yaml`, which references each app's `ks.yaml` directly (or the `kube-system/` directory). Each app reconciles independently via the Flux Kustomization objects in those files. Apps that depend on CRDs from a HelmRelease (e.g. cert-manager) define two KSes in a single `ks.yaml`: an `app/` KS with a healthCheck and a `config/` KS with `dependsOn`. The `kube-system` subtree uses `kube-system` namespace directly (no per-app namespace manifest).

**Important:** the root `cluster` Kustomization has `prune: false`. Removing an app directory from `cluster/kustomization.yaml` does **not** garbage-collect its child Kustomization objects — those must be deleted manually.

## Secrets

Secrets are encrypted with [SOPS](https://github.com/getsops/sops). Rules are defined in `.sops.yaml`. Never commit plaintext secrets. Decrypt with `sops` before editing encrypted files; re-encrypt before committing.

## Talos Node Management

Config is managed via [talhelper](https://github.com/budimanjojo/talhelper) using `talconfig.yaml`.

**All `talosctl` and `talhelper` commands are reserved for manual execution by the cluster owner. Agents must not run any Talos commands.** This includes but is not limited to config generation, config application, upgrades, reboots, and resets.

## GitOps / FluxCD

`cluster/` is reconciled by FluxCD. The directory structure follows standard Flux conventions with HelmReleases referencing HelmRepositories.

When upgrading a Helm chart:
1. Update the chart version in the relevant `HelmRelease` manifest under `cluster/`
2. Run `diff.sh` to preview resource changes before committing

```bash
./diff.sh \
  --source-file cluster/path/to/old-helmrelease.yaml \
  --target-file cluster/path/to/new-helmrelease.yaml \
  --helmrepositories-path "./cluster/**/helmrepository.yaml"
```

`diff.sh` requires `helm` and `yq` in `$PATH`.

## Required Tools

| Tool | Purpose |
|------|---------|
| `kubectl` | Kubernetes resource management |
| `flux` | Flux CLI for GitOps reconciliation |
| `sops` | Secret encryption/decryption |
| `helm` | Required by `diff.sh` |
| `yq` | Required by `diff.sh` and config processing |

`talosctl` and `talhelper` are not agent tools — they are owner-only.

## What Agents Must Not Do

- Run any `talosctl` or `talhelper` command — these are manual-only.
- Modify `deprecatedcluster/` — it is read-only reference material.
- Commit decrypted secrets or kubeconfigs.
- Edit `talconfig.yaml` extensions without a comment noting the change for the owner to apply.
- Delete PVCs or persistent storage resources without explicit instruction — data loss is not recoverable on a single-node cluster.
