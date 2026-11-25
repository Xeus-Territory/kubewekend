# Lab 00: Platform

**Goal:** a one-node Kind cluster with an ingress controller, ready for labs 1 to 3.

Suggested time: 20 minutes.

## What you need

| Need | Why | How |
|------|-----|-----|
| Docker, Kind v0.33, kubectl, Helm 3 | The cluster and the tools | [Kind quick start](https://kind.sigs.k8s.io/docs/user/quick-start/) |
| Load balancer addresses | Traefik is a `LoadBalancer` Service | [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind) (one process serves every Kind cluster) |
| An ingress controller | The hello apps are reached through Ingress | Traefik, installed below (Kubewekend clusters normally already have it) |
| Resources | One node, Argo CD and four small apps | About 2 CPUs and 4 GB of memory |

> [!NOTE]
>
> **Do not touch your own clusters.** The commands use a Kind cluster named `gitops`. Check `kubectl config
> current-context` before running anything, and use `--context kind-gitops` if you work with several clusters.

## Steps

**1. Create the cluster.**

All the labs use `$REPO`, the root of your clone of this repository, so every command works from any directory:

```bash
export REPO=$(git rev-parse --show-toplevel)
kind create cluster --config $REPO/examples/argocd-apps/labs/00-platform/kind-gitops.yaml
kubectl cluster-info --context kind-gitops
```

[`kind-gitops.yaml`](kind-gitops.yaml) is a single control-plane node on `kindest/node:v1.36.4`.

**2. Give Services of type LoadBalancer an address.**

Download cloud-provider-kind from its releases page, then run it in a separate terminal and leave it running:

```bash
cloud-provider-kind
```

**3. Install Traefik.**

Skip this step on a Kubewekend cluster that already has Traefik (check with `kubectl get ingressclass`).

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik
helm upgrade --install traefik traefik/traefik --version 42.0.0 \
  --namespace traefik --create-namespace --wait
kubectl -n traefik get svc traefik
```

```text
NAME      TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
traefik   LoadBalancer   10.96.34.141   172.18.0.5    80:30346/TCP,443:32253/TCP   20s
```

The `EXTERNAL-IP` is the address of the ingress. Save it in a variable:

```bash
export INGRESS_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $INGRESS_IP
```

**4. Reach an app by host name without editing `/etc/hosts`.**

The apps use host names such as `hello-helm.kubewekend.local`. `curl --resolve` maps a name to the ingress address for one
command. This helper wraps it:

```bash
hello() { curl -s --resolve "$1.kubewekend.local:80:$INGRESS_IP" "http://$1.kubewekend.local/version"; echo; }
```

You will use it as `hello hello-helm`, `hello hello-dev` and `hello hello-prod`. (To use a browser instead, add the names
to `/etc/hosts`, pointing at `$INGRESS_IP`.)

## Using your own fork (needed for one step in lab 2)

Labs 1 and 2 work as they are: the Applications read this repository on GitHub. A few steps **push a commit** (adding an
overlay in lab 2 and, if you repeat it, lab 3). For those you need a fork, and every manifest has to point at it:

```bash
cd $REPO/examples/argocd-apps
FORK=https://github.com/<you>/kubewekend
grep -rlE --include='*.yaml' 'github.com/Xeus-Territory/kubewekend' app-of-apps.yaml app-of-apps manifests labs \
  | xargs sed -i "s|https://github.com/Xeus-Territory/kubewekend|$FORK|g"
git add -A && git commit -m "point the Argo CD labs at my fork" && git push
```

Argo CD reads the **pushed** copy, so push before you apply anything. Keep the repository public, so Argo CD needs no
credentials for it.

## Practise locally with Gitea and a registry (no GitHub)

A fork needs a GitHub account and a token. If you would rather keep everything on your machine, run a Git server
([Gitea](https://about.gitea.com/)) and a container registry as two Docker containers next to Kind. No account, no token,
and no real repository is ever at risk: every `git push` in the labs goes to your local Gitea, and every image goes to
your local registry. Labs 1 to 3 then work as written.

How it differs from the fork setup:

- **A scratch copy, not your clone.** The Applications read a copy of `examples/argocd-apps` kept in a temporary folder
  (`$LAB_DIR`) with the repository URL and the image name rewritten. Your clone and its remotes are never changed.
- **HTTPS for Gitea.** Image Updater only accepts `https://` and `ssh` repository URLs (see [lab 03](../03-image-updater/README.md#break-it-an-http-repository)),
  so Gitea gets a self-signed certificate, and Argo CD is told to trust that one repository.
- **HTTP for the registry.** The Kind node and Image Updater are told to allow plain HTTP for it. Only do this on a local
  throwaway setup.

Do this after step 3 above, instead of the fork and **instead of the Argo CD install and the root application in
[lab 01](../01-bootstrap-multi-tenancy/README.md)**, which the last step below does for you. Use the same terminal
throughout, because the commands share variables.

> [!NOTE]
>
> The passwords here (`lab` / `lab-password-1`) are throwaway values for a container on your own machine. Ports `3001`
> (Gitea) and `5001` (registry) must be free.

**1. Start the registry and Gitea on the `kind` Docker network.**

```bash
export LAB_TLS=$(mktemp -d) && chmod 777 $LAB_TLS
docker run -d --name lab-registry --network kind -p 127.0.0.1:5001:5000 registry:2

docker run --rm --user 1000:1000 -v $LAB_TLS:/certs -w /certs gitea/gitea:1.24 \
  gitea cert --host lab-gitea,localhost,127.0.0.1
chmod 644 $LAB_TLS/*.pem
docker run -d --name lab-gitea --network kind -p 127.0.0.1:3001:3000 -v $LAB_TLS:/certs:ro \
  -e GITEA__security__INSTALL_LOCK=true -e GITEA__database__DB_TYPE=sqlite3 \
  -e GITEA__server__PROTOCOL=https -e GITEA__server__CERT_FILE=/certs/cert.pem -e GITEA__server__KEY_FILE=/certs/key.pem \
  -e GITEA__server__ROOT_URL=https://lab-gitea:3000/ -e GITEA__server__DOMAIN=lab-gitea \
  -e GITEA__service__DISABLE_REGISTRATION=true gitea/gitea:1.24
until curl -fsSk https://127.0.0.1:3001/api/healthz >/dev/null; do sleep 2; done

docker exec -u git lab-gitea gitea admin user create --admin --username lab --password lab-password-1 \
  --email lab@example.com --must-change-password=false
curl -fsSk -u lab:lab-password-1 -H 'Content-Type: application/json' \
  -d '{"name":"kubewekend","private":false,"default_branch":"main"}' https://127.0.0.1:3001/api/v1/user/repos
```

Containers on the `kind` network reach each other by name, which is why the Applications will use `lab-gitea` and
`lab-registry` as host names.

**2. Let the Kind node pull from the registry over HTTP.**

```bash
for n in $(kind get nodes --name gitops); do
  docker exec $n mkdir -p /etc/containerd/certs.d/lab-registry:5000
  docker exec $n sh -c 'cat > /etc/containerd/certs.d/lab-registry:5000/hosts.toml <<EOF
server = "http://lab-registry:5000"
[host."http://lab-registry:5000"]
  capabilities = ["pull", "resolve"]
EOF'
done
```

**3. Build the app and publish `v1.0.0` to your registry.**

You push to `localhost:5001`; the cluster pulls the same image as `lab-registry:5000`.

```bash
docker build -t localhost:5001/xeusnguyen/kubewekend-todo:v1.0.0 --build-arg APP_VERSION=v1.0.0 $REPO/examples/argocd-apps/app
docker push localhost:5001/xeusnguyen/kubewekend-todo:v1.0.0
```

**4. Make the scratch copy and push it to Gitea.**

The three `sed` edits rewrite the repository URL, the image name and, if a manifest has a pull request provider, the key
`github: {}` to `gitea: {}`: the provider key says which API Image Updater calls, and here that is Gitea (see
[lab 03](../03-image-updater/README.md#open-a-pull-request-instead-of-committing)). The `printf` appends a registry entry
to the Argo CD values, so Image Updater knows how to reach your HTTP registry.

```bash
export LAB_DIR=$(mktemp -d)
mkdir -p $LAB_DIR/examples && cp -r $REPO/examples/argocd-apps $LAB_DIR/examples/argocd-apps
cd $LAB_DIR
rm -rf examples/argocd-apps/app
find examples -name '*.yaml' | xargs sed -i \
  -e 's|https://github.com/Xeus-Territory/kubewekend|https://lab-gitea:3000/lab/kubewekend|g' \
  -e 's|xeusnguyen/kubewekend-todo|lab-registry:5000/xeusnguyen/kubewekend-todo|g' \
  -e 's|github: {}|gitea: {}|g'
printf '\n  config:\n    registries:\n      - name: lab\n        api_url: http://lab-registry:5000\n        prefix: lab-registry:5000\n        insecure: yes\n        ping: no\n' \
  >> examples/argocd-apps/manifests/infrastructure/argocd/values.yaml

git init -q -b main
git config user.name lab && git config user.email lab@example.com && git config http.sslVerify false
git add -A && git commit -q -m "lab content"
git remote add origin https://lab:lab-password-1@127.0.0.1:3001/lab/kubewekend.git
git push -q origin main
```

`http.sslVerify false` is set only inside this scratch repository, because Gitea's certificate is self-signed.

**5. Install Argo CD from the scratch copy, trust the repository, and apply the root application.**

This is [lab 01](../01-bootstrap-multi-tenancy/README.md) steps 1 and 2, pointed at your local Gitea:

```bash
cd $LAB_DIR/examples/argocd-apps/manifests/infrastructure/argocd
helm dependency update .
helm upgrade --install argocd . --namespace argocd --create-namespace --wait

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-lab
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://lab-gitea:3000/lab/kubewekend
  username: lab
  password: lab-password-1
  insecure: "true"
EOF

cd $LAB_DIR/examples/argocd-apps
kubectl apply -f app-of-apps.yaml
timeout 600 bash -c 'until [ "$(kubectl -n argocd get applications.argoproj.io --no-headers | grep -c "Synced *Healthy")" = 6 ]; do sleep 5; done'
kubectl -n argocd get applications.argoproj.io
```

All six applications become `Synced` and `Healthy`. Continue with [lab 01](../01-bootstrap-multi-tenancy/README.md) from
its step 3.

**Using it in the other labs**

- **Lab 02 (add an overlay):** run the `git` commands inside `$LAB_DIR` (for example
  `cd $LAB_DIR/examples/argocd-apps/workloads/hello-kustomize/overlays`) and push with a plain `git push`.
- **Lab 03 (Image Updater):** create the credentials for your Gitea, apply the resource from the scratch copy, publish
  `v1.1.0` to your registry and watch Gitea receive the commits:

```bash
kubectl -n argocd create secret generic git-creds --from-literal=username=lab --from-literal=password=lab-password-1
kubectl apply -f $LAB_DIR/examples/argocd-apps/labs/03-image-updater/imageupdater.yaml

docker build -t localhost:5001/xeusnguyen/kubewekend-todo:v1.1.0 \
  --build-arg APP_VERSION=v1.1.0 \
  --build-arg APP_MESSAGE="Hello from Kubewekend: rolled out by Image Updater" $REPO/examples/argocd-apps/app
docker push localhost:5001/xeusnguyen/kubewekend-todo:v1.1.0

cd $LAB_DIR
timeout 600 bash -c 'until git pull -q --rebase origin main && [ -f examples/argocd-apps/workloads/hello-helm/.argocd-source-hello-helm.yaml ]; do sleep 10; done'
git log --format='%h %an: %s' | head -3
ls -A examples/argocd-apps/workloads/hello-helm
for i in $(seq 1 60); do hello hello-dev | grep -q v1.1.0 && break; sleep 5; done
hello hello-dev
```

You should see two commits by `argocd-image-updater`, the hidden `.argocd-source-hello-helm.yaml` file next to the
chart, and `hello-dev` answering with `v1.1.0`. It takes a few minutes: Image Updater checks the registry every two
minutes and Argo CD checks Git every three.

**Clean up** the containers and the temporary folders (the cluster is deleted in the cleanup at the end of this page):

```bash
docker rm -f lab-gitea lab-registry
rm -rf $LAB_DIR $LAB_TLS
```

## Verify

```bash
kubectl get nodes
kubectl -n traefik get pods
hello hello-helm
```

There is no app yet, so Traefik answers `404 page not found`. That answer is what you want: it proves the ingress is
reachable through `$INGRESS_IP`.

## Cleanup

```bash
kind delete cluster --name gitops
```

Next: [Lab 01: Bootstrap and multi-tenancy](../01-bootstrap-multi-tenancy/README.md).
