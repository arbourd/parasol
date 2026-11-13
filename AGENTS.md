# AGENTS.md

## Repo Overview

`parasol` is a GitOps-managed Talos Linux homelab cluster. Changes pushed to `main` are reconciled by Flux running in-cluster.

## Cluster

- **OS / Kubernetes**: versions pinned in `nodes/talconfig.yaml`
- **Topology**: single node (`node-01`, `10.128.1.140`), control plane with `allowSchedulingOnControlPlanes: true`
- **Endpoint**: `https://10.128.1.140:6443`
- **Install disk**: `/dev/nvme0n1`
- **Talos extensions** (`nodes/talconfig.yaml`): `siderolabs/i915` (Intel GPU), `siderolabs/intel-ice-firmware` (NIC), `siderolabs/intel-ucode`, `siderolabs/iscsi-tools`, `siderolabs/thunderbolt`
- **Networking**: no CNI and no kube-proxy (Cilium eBPF replaces both), Cilium BGP, kubePrism on `7445`, hostDNS on with `forwardKubeDNSToHost: false`

## Repository Layout

```
.
├── cluster/        # Live cluster state (Flux-reconciled)
├── nodes/          # Talhelper config for node/cluster definition
├── .sops.yaml      # SOPS rules for secret encryption
├── diff.sh         # HelmRelease diff tool
├── tests/          # bats tests
└── .github/        # ci.yml (bats on push), helm.yml (PRs to main touching cluster/**.yaml: runs diff.sh on each added/modified helmrelease.yaml and comments the result)
```

### Cluster Directory Structure

The root `cluster` Flux Kustomization (`cluster/flux-system/cluster/ks.yaml`) applies `cluster/kustomization.yaml`, which references each app's `ks.yaml` (or the `kube-system/` directory). Each app then reconciles independently. Apps that depend on CRDs from a HelmRelease (e.g. cert-manager) define two KSes in one `ks.yaml`: an `app/` KS with a healthCheck and a `config/` KS with `dependsOn`.

```
cluster/
├── cert-manager/, external-dns/   # ks.yaml (<app> → app/, <app>-config → config/) + app/ + config/ (CRD-dependent resources)
├── flux-system/
│   ├── cluster/                   # cluster ConfigMap + Secret (postBuild substituteFrom) + root cluster KS
│   └── gitrepositories/, helmrepositories/, ocirepositories/   # chart and git sources
├── kube-system/                   # uses kube-system namespace directly (no namespace.yaml)
│   ├── *-ks.yaml                  # KSes for cilium, cilium-bgp, multus, gateway-api (gateway-api points at its own GitRepository)
│   └── local-path-provisioner/    # HelmRelease applied inline by the cluster KS (no own KS)
└── scrypted/                      # ks.yaml + app/
```

**Important:** the root `cluster` Kustomization has `prune: false`. Removing an app from `cluster/kustomization.yaml` does **not** delete its child Kustomization objects; delete them manually.

To deploy a new app, follow `.claude/skills/add-app/SKILL.md` if it exists.

Check state with `flux get kustomizations -A` and `flux get helmreleases -A`. Force a sync with `flux reconcile kustomization <name> --with-source`.

## Secrets

Never commit plaintext secrets. Encrypted with [SOPS](https://github.com/getsops/sops) per `.sops.yaml`. `.githooks/pre-commit` blocks any `kind: Secret` manifest that isn't encrypted. `age.agekey` (repo root, gitignored) is the decryption key: never read, print, commit, or otherwise touch it. Run `sops` (which uses the key) only when explicitly asked, and re-encrypt before committing.

## Talos Node Management

Config is managed with [talhelper](https://github.com/budimanjojo/talhelper) via `nodes/talconfig.yaml`. **`talosctl` and `talhelper` are owner-only. Agents must not run them** (config generation or apply, upgrades, reboots, resets).

## Helm Upgrades

1. Update the chart version in the `HelmRelease` under `cluster/`.
2. Preview with `diff.sh` (needs `helm` and `yq`) before committing:

```bash
./diff.sh \
  --source-file cluster/path/to/old-helmrelease.yaml \
  --target-file cluster/path/to/new-helmrelease.yaml \
  --helmrepositories-path "./cluster/flux-system/helmrepositories/*.yaml"
```

## Testing

`bats tests/` covers `diff.sh` (`tests/diff.bats`) and the pre-commit hook (`tests/pre_commit.bats`).

After changing anything under `.github/workflows/`, run `actionlint`.

After changing `.github/renovate.json`, run `npx --yes --package renovate -- renovate-config-validator --strict`.

## Tools

`kubectl`, `flux`, `sops`, `helm`, `yq`, `bats`.

## What Agents Must Not Do

- Run any `talosctl` or `talhelper` command.
- Commit decrypted secrets or kubeconfigs.
- Read, print, copy, edit, or commit `age.agekey`, including via `cat`, `grep`, or `git add -f`. Run `sops` (which uses it) only when explicitly asked.
- Edit `talconfig.yaml` extensions without a comment noting the change for the owner to apply.
- Delete PVCs or persistent storage without explicit instruction; data loss is unrecoverable on a single node.
