# Kubewekend ArgoCD Platform

## First bootstrap

>[!NOTE]
>For playing around ArgoCD, you can double-check these resources for choosing the path to follow
> - [ArgoCD Manifests](https://github.com/argoproj/argo-cd/tree/master/manifests): All of manifest for setting up your ArgoCD (HA, Standalone, ...)
> - [ArgoCD QuickStart](https://argo-cd.readthedocs.io/en/stable/getting_started/)

### Opt1. Run the stable version of ArgoCD Manifest

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Opt2. Generate your own version and apply it by `helm` or `kubectl`

1. Generate the `install.yaml` with helm template command

