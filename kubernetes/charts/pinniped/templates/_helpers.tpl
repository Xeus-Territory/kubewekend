{{- define "pinniped.namespace" -}}
{{- default .Release.Namespace .Values.namespace.name -}}
{{- end -}}

{{- define "pinniped.componentNamespace" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $baseNamespace := default "pinniped" $root.Values.namespace.name -}}
{{- printf "%s-%s" $baseNamespace $component | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pinniped.componentName" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $values := index $root.Values $component -}}
{{- $defaultName := include "pinniped.componentNamespace" (dict "root" $root "component" $component) -}}
{{- default $defaultName $values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pinniped.standardLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name (.Chart.Version | replace "+" "_") }}
{{- end -}}

{{- define "pinniped.componentLabels" -}}
{{ include "pinniped.standardLabels" .root }}
app.kubernetes.io/component: {{ .component }}
app: {{ include "pinniped.componentName" . }}
{{- with .root.Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- with .componentValues.customLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "pinniped.runtimeLabels" -}}
app: {{ include "pinniped.componentName" . }}
{{- with .root.Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- with .componentValues.customLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "pinniped.componentSelectorLabels" -}}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app: {{ include "pinniped.componentName" . }}
{{- end -}}

{{- define "pinniped.image" -}}
{{- $image := .image -}}
{{- if $image.digest -}}
{{ printf "%s@%s" $image.repository $image.digest }}
{{- else -}}
{{ printf "%s:%s" $image.repository (default .root.Chart.AppVersion $image.tag) }}
{{- end -}}
{{- end -}}

{{- define "pinniped.concierge.serviceAccountName" -}}
{{- $base := include "pinniped.componentName" (dict "root" .root "component" "concierge") -}}
{{- if .suffix -}}
{{ printf "%s-%s" $base .suffix | trunc 63 | trimSuffix "-" }}
{{- else -}}
{{ $base }}
{{- end -}}
{{- end -}}

{{- define "pinniped.supervisor.serviceAccountName" -}}
{{ include "pinniped.componentName" (dict "root" .root "component" "supervisor") }}
{{- end -}}

{{- define "pinniped.concierge.proxyServiceName" -}}
{{ printf "%s-proxy" (include "pinniped.componentName" (dict "root" . "component" "concierge")) | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "pinniped.concierge.apiTLSSecretName" -}}
{{- if .Values.concierge.tls.secretNames.api -}}
{{- .Values.concierge.tls.secretNames.api -}}
{{- else -}}
{{- printf "%s-api-tls-serving-certificate" (include "pinniped.componentName" (dict "root" . "component" "concierge")) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "pinniped.concierge.impersonationTLSSecretName" -}}
{{- if .Values.concierge.tls.secretNames.impersonationProxy -}}
{{- .Values.concierge.tls.secretNames.impersonationProxy -}}
{{- else -}}
{{- printf "%s-impersonation-proxy-tls-serving-certificate" (include "pinniped.componentName" (dict "root" . "component" "concierge")) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "pinniped.concierge.ingressServiceName" -}}
{{- if .Values.concierge.ingress.service.name -}}
{{- .Values.concierge.ingress.service.name -}}
{{- else -}}
{{ include "pinniped.concierge.proxyServiceName" . }}
{{- end -}}
{{- end -}}

{{- define "pinniped.supervisor.publicServiceName" -}}
{{- $base := include "pinniped.componentName" (dict "root" .root "component" "supervisor") -}}
{{- printf "%s-%s" $base .suffix | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pinniped.supervisor.autoClusterIPForExposure" -}}
{{- if and .Values.supervisor.enabled .Values.supervisor.ingress.enabled (not .Values.supervisor.ingress.service.name) (not .Values.supervisor.service.public.clusterIP.enabled) (not .Values.supervisor.service.public.loadBalancer.enabled) (not .Values.supervisor.service.public.nodePort.enabled) -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{- define "pinniped.supervisor.exposureServiceName" -}}
{{- if .Values.supervisor.ingress.service.name -}}
{{- .Values.supervisor.ingress.service.name -}}
{{- else if .Values.supervisor.service.public.clusterIP.enabled -}}
{{ include "pinniped.supervisor.publicServiceName" (dict "root" . "suffix" "clusterip") }}
{{- else if eq (include "pinniped.supervisor.autoClusterIPForExposure" .) "true" -}}
{{ include "pinniped.supervisor.publicServiceName" (dict "root" . "suffix" "clusterip") }}
{{- else if .Values.supervisor.service.public.loadBalancer.enabled -}}
{{ include "pinniped.supervisor.publicServiceName" (dict "root" . "suffix" "loadbalancer") }}
{{- else if .Values.supervisor.service.public.nodePort.enabled -}}
{{ include "pinniped.supervisor.publicServiceName" (dict "root" . "suffix" "nodeport") }}
{{- else -}}
{{ printf "%s-api" (include "pinniped.componentName" (dict "root" . "component" "supervisor")) | trunc 63 | trimSuffix "-" }}
{{- end -}}
{{- end -}}

{{- define "pinniped.supervisor.defaultTLSSecretName" -}}
{{- if .Values.supervisor.tls.secretName -}}
{{- .Values.supervisor.tls.secretName -}}
{{- else -}}
{{- printf "%s-default-tls-certificate" (include "pinniped.componentName" (dict "root" . "component" "supervisor")) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "pinniped.supervisor.ingressServiceName" -}}
{{ include "pinniped.supervisor.exposureServiceName" . }}
{{- end -}}
