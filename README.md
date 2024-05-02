# Setup the fully kubernetes cluster inside the locally hosted

- Vargrant - Template the kubernetes cluster with HyperV, VMware, VMbox
- Ansible - To setup and run script and bring up kubernetes cluster on locally
- Use kubeadm to expand, manage kubernetes nodes
- Setup etcd in kubernetes
- Use Cilium to setup ebpf for observe, networking, service mesh in kubernetes
- Use extend CSI for volume in kubernetes and define kubernetes storage class with `Ceph`
- Cusmtomize default scheduled in kubernetes cluster with `kube-scheduler`
- Setup the monitoring cluster inside the kubernetes with node-exporter, cadvisor, prometheus and grafana
- Setup tracing, logging, profiling with sidecar or use cilium-ebpf