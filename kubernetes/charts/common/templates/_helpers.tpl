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
Render probes in pod template for healthcheck
*/}}
{{- define "common.probes" -}}
{{- $probes := .Values.probes -}}
{{- if not (mustHas "all" $probes.disableProbes) -}}
{{- if not (mustHas "livenessProbe" $probes.disableProbes) -}}
{{- $_ := set $probes.livenessProbe.httpGet "path" (default $probes.livenessProbe.httpGet.path | default "/") -}}
livenessProbe: {{ toYaml $probes.livenessProbe | nindent 2 }}
{{- end }}
{{- if not (mustHas "readinessProbe" $probes.disableProbes) }}
{{- $_ := set $probes.readinessProbe.httpGet "path" (default $probes.readinessProbe.httpGet.path | default "/") }}
readinessProbe: {{ toYaml $probes.readinessProbe | nindent 2 }}
{{- end }}
{{- if not (mustHas "startupProbe" $probes.disableProbes) }}
{{- $_ := set $probes.startupProbe.httpGet "path" (default $probes.startupProbe.httpGet.path | default "/") }}
startupProbe: {{ toYaml $probes.startupProbe | nindent 2 }}
{{- end }}
{{- end -}}
{{- end -}}