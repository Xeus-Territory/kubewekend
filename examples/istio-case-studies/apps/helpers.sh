# Small shell helpers for the labs. Load them in your shell from a lab folder:
#
#   source ../apps/helpers.sh
#
# Every helper sends its requests from the `curl` Pod of a namespace (the `common` chart names the app
# container "common", hence `-c common`). An optional kube-context lets the same helper work in lab 04.

# call <namespace> <deployment> <curl args...>
#   One request, printed as: <namespace>/<deployment> curl <args> -> http=<status> exit=<curl exit code>
#   Useful exit codes: 0 ok, 56 connection reset (refused by a policy), 28 timeout (dropped by the network).
call() {
  local ns=$1 dep=$2; shift 2
  local code
  code=$(kubectl -n "$ns" exec "deploy/$dep" -c common -- curl -s -o /dev/null -m 6 -w '%{http_code}' "$@" 2>&1)
  echo "$ns/$dep  curl $*  ->  http=$code exit=$?"
}

# codes <namespace> <count> <url> [kube-context]
#   <count> sequential requests from the curl Pod, summarised as "<n> <status>" lines.
codes() {
  local ns=$1 n=$2 url=$3 ctx=${4:+--context $4}
  kubectl $ctx -n "$ns" exec deploy/curl -c common -- sh -c \
    "for i in \$(seq 1 $n); do curl -s -m 8 -o /dev/null -w '%{http_code}\n' $url; done" | sort | uniq -c
}

# versions <namespace> <count> [kube-context]
#   <count> requests to http://helloworld:5000/hello, summarised by the version that answered.
versions() {
  local ns=$1 n=$2 ctx=${3:+--context $3}
  kubectl $ctx -n "$ns" exec deploy/curl -c common -- sh -c \
    "for i in \$(seq 1 $n); do curl -s -m 6 http://helloworld:5000/hello; done" | grep -o 'version: v[12]' | sort | uniq -c
}
