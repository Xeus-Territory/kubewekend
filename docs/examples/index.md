---
title: Examples
description: "Hands-on Kubernetes examples for Kubewekend clusters: Istio service mesh labs, an LGTM observability app and Argo CD GitOps labs."
nav_order: 4
has_children: true
permalink: /docs/examples/
---

# Examples
{: .no_toc }

Ready-made workloads to practise on a Kubewekend cluster. Each example lists the utilities it needs.
{: .fs-5 .fw-300 }

| Example | What you practise | Needs | Docs |
|---------|-------------------|-------|------|
| **Istio case studies** | A service mesh in four labs: sidecar vs ambient, mTLS and authorization, ingress and egress gateways, a two-cluster multi-network mesh | Kind, no ingress controller (the labs bring their own cluster config) | [Read here]({% link examples/istio-case-studies/README.md %}) |
| **LGTM observability app** | Traces, logs, metrics and profiles from one app (FastAPI + PostgreSQL), correlated in Grafana | `utils monitoring` | [Read here]({% link examples/lgtm-testing/README.md %}) |
| **Argo CD labs** | GitOps in four labs: App of Apps and AppProjects, Application vs ApplicationSet, Image Updater, and a hub and spoke pair with argocd-agent | Kind (the labs bring their own cluster config) | [Read here]({% link examples/argocd-apps/labs/README.md %}) |

> [!TIP]
>
> Install the utility an example needs first, then follow its README. Each example also runs with Docker Compose or plain manifests, so you can read the code before deploying it.
