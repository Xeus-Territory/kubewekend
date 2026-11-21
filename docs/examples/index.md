---
title: Examples
description: "Hands-on Kubernetes examples for Kubewekend clusters: an LGTM observability app and GitOps with Argo CD app of apps."
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
| **LGTM observability app** | Traces, logs, metrics and profiles from one app (FastAPI + PostgreSQL), correlated in Grafana | `utils monitoring` | [Read here]({% link examples/lgtm-testing/README.md %}) |
| **Argo CD apps** | GitOps with the App of Apps and ApplicationSet patterns, sync waves, three-layer layout (infrastructure / platform / apps) | `utils gitops` with `type: argocd` | [Read on GitHub]({{ site.repo_url }}/tree/main/examples/argocd-apps) |

> [!TIP]
>
> Install the utility an example needs first, then follow its README. Each example also runs with Docker Compose or plain manifests, so you can read the code before deploying it.
