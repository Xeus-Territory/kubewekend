{{/*
Expand the name of the chart.
*/}}
{{- define "common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "common.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "common.labels" -}}
helm.sh/chart: {{ include "common.chart" . }}
{{ include "common.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "common.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "common.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Define the namespace for your application
*/}}
{{- define "common.namespace" }}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Render service ports with backward-compatible fallback to service.port/targetPort.
*/}}
{{- define "common.servicePorts.render" -}}
{{- if eq .Values.service.type "ExternalName" }}
{{- $ports := list -}}
{{- if .Values.service.ports }}
{{- range .Values.service.ports }}
{{- $ports = append $ports (dict "name" .name "port" .port "protocol" (default "TCP" .protocol)) -}}
{{- end }}
{{- else }}
{{- $ports = append $ports (dict "name" "http" "port" .Values.service.port "protocol" "TCP") -}}
{{- end }}
{{- toYaml $ports }}
{{- else if .Values.service.ports }}
{{- toYaml .Values.service.ports }}
{{- else }}
{{- toYaml (list (dict "name" "http" "port" .Values.service.port "targetPort" (default "http" .Values.service.targetPort) "protocol" "TCP")) }}
{{- end }}
{{- end }}

{{/*
Return the selected service port object used by ingress, notes, and test hooks.
*/}}
{{- define "common.service.selectedPort" -}}
{{- $selected := dict -}}
{{- if .Values.service.ports }}
    {{- if .Values.service.primaryPortName }}
        {{- range .Values.service.ports }}
            {{- if and (not (hasKey $selected "port")) (eq .name $.Values.service.primaryPortName) }}
                {{- $_ := set $selected "port" . }}
            {{- end }}
        {{- end }}
    {{- end }}
    {{- if not (hasKey $selected "port") }}
        {{- $_ := set $selected "port" (index .Values.service.ports 0) }}
    {{- end }}
{{- else }}
    {{- $_ := set $selected "port" (dict "name" (default "http" .Values.service.primaryPortName) "port" .Values.service.port "targetPort" (default "http" .Values.service.targetPort) "protocol" "TCP") }}
{{- end }}
{{- toYaml (get $selected "port") }}
{{- end }}

{{/*
Return the primary service port number.
*/}}
{{- define "common.service.primaryPort" -}}
{{- $selectedPort := include "common.service.selectedPort" . | fromYaml -}}
{{- $selectedPort.port -}}
{{- end }}

{{/*
Render the selected service port reference for ingress backends.
*/}}
{{- define "common.service.primaryPortRef" -}}
{{- $selectedPort := include "common.service.selectedPort" . | fromYaml -}}
{{- if get $selectedPort "name" }}
name: {{ get $selectedPort "name" }}
{{- else }}
number: {{ get $selectedPort "port" }}
{{- end }}
{{- end }}

{{/*
Return the primary application container port number.
*/}}
{{- define "common.container.primaryPort" -}}
{{- if .Values.containerPorts }}
    {{- $selected := dict -}}
    {{- range .Values.containerPorts }}
        {{- if and (not (hasKey $selected "port")) (eq .name (default "http" $.Values.probes.port)) }}
            {{- $_ := set $selected "port" .containerPort }}
        {{- end }}
    {{- end }}
    {{- if hasKey $selected "port" }}
{{- get $selected "port" -}}
    {{- else }}
{{- (index .Values.containerPorts 0).containerPort -}}
    {{- end }}
{{- else if .Values.service.enabled }}
{{- include "common.service.primaryPort" . -}}
{{- end }}
{{- end }}

{{/*
Return the default probe port reference.
*/}}
{{- define "common.probes.defaultPort" -}}
{{- if .Values.probes.port -}}
{{- .Values.probes.port -}}
{{- else if .Values.containerPorts -}}
{{- $httpPort := dict -}}
{{- range .Values.containerPorts }}
{{- if and (not (hasKey $httpPort "value")) (eq .name "http") }}
{{- $_ := set $httpPort "value" .name -}}
{{- end }}
{{- end }}
{{- if hasKey $httpPort "value" -}}
{{- get $httpPort "value" -}}
{{- else if (get (index .Values.containerPorts 0) "name") -}}
{{- get (index .Values.containerPorts 0) "name" -}}
{{- else -}}
{{- (index .Values.containerPorts 0).containerPort -}}
{{- end }}
{{- else if and .Values.service.enabled .Values.service.targetPort -}}
{{- .Values.service.targetPort -}}
{{- else -}}
http
{{- end }}
{{- end }}

{{/*
Renders a value that contains template.
Usage:
{{ include "common.tplvalues.render" ( dict "value" .Values.path.to.the.Value "context" $) }}
*/}}
{{- define "common.tplvalues.render" -}}
    {{- if typeIs "string" .value }}
        {{- tpl .value .context }}
    {{- else }}
        {{- tpl (.value | toYaml) .context }}
    {{- end }}
{{- end -}}

{{/*
Renders a key value list to YAML format, e.g: env
Usage:
{{- with .Values.env }}
    env: {{ include "common.keyvalues.render" . | indent 8 }}
{{- end }}
*/}}
{{- define "common.keyvalues.render" }}
{{- range $key, $value := . }}
- name: {{ $key | upper | quote }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}

{{/*
Render env variables for combine multiple type, simple key-value, or valueFrom, or both.
# Usage:
{{- with .Values.env }}
    env:
      {{- include "common.env.render" (dict "values" . "context" $) | indent 8 }}
{{- end }}
*/}}
{{- define "common.env.render" -}}
{{- $context := .context -}}
{{- range $key, $value := .values }}
{{- $envItem := dict "name" ($key | upper) -}}
{{- if kindIs "string" $value }}
{{- $parts := splitList ":" $value }}
{{- if and (eq (len $parts) 3) (eq (index $parts 0) "secret") }}
{{- $_ := set $envItem "valueFrom" (dict "secretKeyRef" (dict "name" (tpl (index $parts 1) $context) "key" (tpl (index $parts 2) $context))) -}}
{{- else if and (eq (len $parts) 3) (eq (index $parts 0) "configmap") }}
{{- $_ := set $envItem "valueFrom" (dict "configMapKeyRef" (dict "name" (tpl (index $parts 1) $context) "key" (tpl (index $parts 2) $context))) -}}
{{- else if and (ge (len $parts) 2) (eq (index $parts 0) "field") }}
{{- $_ := set $envItem "valueFrom" (dict "fieldRef" (dict "fieldPath" (join ":" (slice $parts 1)))) -}}
{{- else if and (or (eq (len $parts) 2) (eq (len $parts) 3)) (eq (index $parts 0) "resource") }}
{{- $resourceFieldRef := dict "resource" (index $parts 1) -}}
{{- if eq (len $parts) 3 }}
{{- $_ := set $resourceFieldRef "divisor" (index $parts 2) -}}
{{- end }}
{{- $_ := set $envItem "valueFrom" (dict "resourceFieldRef" $resourceFieldRef) -}}
{{- else }}
{{- $_ := set $envItem "value" (tpl $value $context) -}}
{{- end }}
{{- else if kindIs "map" $value }}
{{- range $field, $fieldValue := $value }}
{{- $_ := set $envItem $field $fieldValue -}}
{{- end }}
{{- else }}
{{- $_ := set $envItem "value" (printf "%v" $value) -}}
{{- end }}
{{ toYaml (list $envItem) | trim }}
{{- end }}
{{- end }}


{{/*
Render probes in pod template for healthcheck
*/}}
{{- define "common.probes" -}}
{{- $probes := .Values.probes -}}
{{- $probePort := include "common.probes.defaultPort" . -}}
{{- if not (mustHas "all" $probes.disableProbes) -}}
{{- if not (mustHas "livenessProbe" $probes.disableProbes) -}}
{{- with $probes.livenessProbe.httpGet }}
{{- $_ := set . "path" (default .path "/") -}}
{{- $_ := set . "port" (default .port $probePort) -}}
{{- end }}
livenessProbe: {{ toYaml $probes.livenessProbe | nindent 2 }}
{{- end }}
{{- if not (mustHas "readinessProbe" $probes.disableProbes) -}}
{{- with $probes.readinessProbe.httpGet }}
{{- $_ := set . "path" (default .path "/") -}}
{{- $_ := set . "port" (default .port $probePort) -}}
{{- end }}
readinessProbe: {{ toYaml $probes.readinessProbe | nindent 2 }}
{{- end }}
{{- if not (mustHas "startupProbe" $probes.disableProbes) -}}
{{- with $probes.startupProbe.httpGet }}
{{- $_ := set . "path" (default .path "/") -}}
{{- $_ := set . "port" (default .port $probePort) -}}
{{- end }}
startupProbe: {{ toYaml $probes.startupProbe | nindent 2 }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Setup Vault Annotations for your application
*/}}
{{- define "common.vault.annotations" -}}
{{- $vault := .Values.vault -}}
{{- if $vault.enabled -}}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/agent-pre-populate-only: 'true'
vault.hashicorp.com/auth-path: {{ $vault.config.authPath }}
vault.hashicorp.com/namespace: {{ $vault.config.namespace }}
vault.hashicorp.com/role: {{ $vault.config.role }}
vault.hashicorp.com/service: {{ $vault.config.serviceServer }}
{{- if $vault.template }}
{{ printf "vault.hashicorp.com/agent-inject-secret-%s: %s" $vault.template.name $vault.config.path }}
{{ printf "vault.hashicorp.com/agent-inject-template-%s: |-" $vault.template.name -}}
{{ trim $vault.template.content | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}