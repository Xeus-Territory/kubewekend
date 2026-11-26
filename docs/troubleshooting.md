---
title: Troubleshooting
description: "Fix common Kubewekend problems: out-of-memory bootstrap failures, pending PVCs, busy ports after Kind, archived ingress classes and VirtualBox errors."
nav_order: 7
permalink: /docs/troubleshooting/
---

# Troubleshooting Kubewekend
{: .no_toc }

Common problems, what causes them, and how to fix them.
{: .fs-5 .fw-300 }

1. TOC
{:toc}

## A node fails to bootstrap or a Pod is killed with `Error 137`

**Cause:** not enough memory. RKE2 masters need at least 2 CPU and 2 GB RAM; utilities such as monitoring need more.

**Fix:** raise `config.memory` / `config.cpus` in the `Vagrantfile` (or size the VPS up), then recreate the node. See [node sizing]({% link docs/getting-started/index.md %}#node-sizing).

## A utility tag does nothing

**Cause:** its block is disabled in `master.yaml`.

**Fix:** set `utilities.<key>.enable: true`. The CLI prints a warning for disabled tags; check with `./scripts/setup.sh config show`.

## A PVC or a standalone Vault / OpenBao Pod stays `Pending`

**Cause:** no StorageClass matches the claim.

**Fix:** install [storage]({% link docs/utilities/storage.md %}) first, and check `kubectl get storageclass`.

## Ports 80 / 443 are still busy after a local Kind lab

**Cause:** the `socat-netforward-port-80/443` services created by `networkForwarding`.

**Fix:** `./scripts/setup.sh kind destroy`, or `sudo systemctl disable --now socat-netforward-port-80 socat-netforward-port-443`.

## `kind setup` or `rke2 setup` warns about an archived class

**Cause:** `master.yaml` selects an ingress or gateway controller other than Traefik (NGINX, Kong, Cilium, RKE2 `ingress-nginx`). They are archived.

**Fix:** set the class to `traefik`.

## `versions sync` fails in pre-commit

**Cause:** a pinned version was changed in one place only, or a registry pattern no longer matches.

**Fix:** use `./scripts/setup.sh versions bump <component> <version>` to change every location, then commit the regenerated tables.

## VirtualBox problems

- [Error when setting up VirtualBox on Ubuntu](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Operation-System/Linux/Awesome-Linux-Troubleshoot#error-when-setup-virtualbox-in-ubuntu)
- [VMSetError: VirtualBox can't enable the AMD-V extension](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Operation-System/Linux/Awesome-Linux-Troubleshoot#vmseterror-virtualbox-cant-enable-the-amd-v-extension)
- Use another Vagrantfile with `VAGRANT_VAGRANTFILE=Vagrantfile.ceph vagrant up <machine>` ([why](https://stackoverflow.com/questions/17308629/specify-vagrantfile-path-explicity-if-not-plugin)).

Still stuck? [Open an issue]({{ site.repo_url }}/issues/new/choose).
