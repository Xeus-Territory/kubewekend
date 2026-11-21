---
title: Storage
description: "Persistent storage for Kubewekend clusters with Longhorn or the local-path-provisioner, and a PVC test that proves provisioning works."
parent: Utilities
nav_order: 1
---

# Storage: Longhorn and local-path-provisioner
{: .no_toc }

Give workloads persistent volumes with Longhorn or the local-path-provisioner, then prove it works with a PVC test.
{: .fs-5 .fw-300 }

1. TOC
{:toc}

## Choose a provisioner

| `utilities.storage.type` | What it installs | StorageClass | Good for |
|--------------------------|------------------|--------------|----------|
| `longhorn` | Longhorn (Helm) in `longhorn-system`, with optional iSCSI / NFS node setup | `longhorn` | Replicated block storage on K3s / RKE2 nodes |
| `local-path` | Rancher local-path-provisioner (manifest) | `local-path` | Simple node-local volumes, Kind and single-node labs |

```yaml
utilities:
  storage:
    enable: true
    type: "longhorn"        # longhorn | local-path
    longhorn:
      setup:
        iscsi: true         # DaemonSet that prepares iSCSI on every node
        nfs: false          # DaemonSet that prepares NFS on every node
      replicaStorage: 1     # default replica count (3 for production-like clusters)
    test:
      enable: true          # nginx Pod + 2Gi RWO PVC
      namespace: "default"
```

> [!NOTE]
>
> Install Longhorn on K3s or RKE2 nodes. On Kind, prefer `local-path`: it applies Rancher's upstream manifest, which creates the `local-path` StorageClass the PVC test asks for.

## Install

```bash
./scripts/setup.sh k3s utils storage
```

## Verify

With `test.enable: true`, the playbook applies an nginx Pod that mounts a 2Gi `ReadWriteOnce` PVC. The PVC asks for the StorageClass named after `storage.type`:

```bash
# STATUS: Bound
kubectl get pvc test-storage-pvc
# STATUS: Running
kubectl get pod volume-test
kubectl exec volume-test -- sh -c 'echo ok > /data/test && cat /data/test'
```

Clean up the test with `kubectl delete pod volume-test && kubectl delete pvc test-storage-pvc`.

## Learn more

- [Session 6: CSI and Ceph with Kubewekend](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-6)
- [Extra 1: Longhorn and the story about NFS in Kubernetes](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-1)
