---
title: Helm charts
description: "Helm charts published by Kubewekend: the common chart for stateless apps and the Pinniped chart for Kubernetes authentication."
parent: Reference
nav_order: 4
has_children: true
---

# Helm charts
{: .no_toc }

Charts from [`kubernetes/charts`]({{ site.repo_url }}/tree/main/kubernetes/charts), released with chart-releaser and served from this site.
{: .fs-5 .fw-300 }

```bash
helm repo add kubewekend https://kubewekend.xeusnguyen.xyz
helm repo update
helm search repo kubewekend
```

| Chart | Version | Description | Docs |
|-------|---------|-------------|------|
| `common` | 0.4.0 | Stateless applications (web APIs, frontends, GPU workloads) rendered as one Deployment, with Service, Ingress / HTTPRoute, autoscaling, monitors and scheduling helpers | [README on GitHub]({{ site.repo_url }}/tree/main/kubernetes/charts/common) |
| `pinniped` | 0.1.0 (app v0.46.0) | Pinniped Supervisor and Concierge: Kubernetes authentication through an impersonation proxy | [Read here]({% link kubernetes/charts/pinniped/README.md %}) |
