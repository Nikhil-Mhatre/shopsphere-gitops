{{/*
------------------------------------------------------------------------------
users Helm Chart Helper Templates
------------------------------------------------------------------------------

This file contains reusable helper templates used throughout the users Helm
chart.

Why use helper templates?

Instead of repeating the same template logic inside every Kubernetes
manifest, Helm allows us to define reusable functions here.

Benefits:

- Reduces duplicate template code.
- Keeps Kubernetes manifests small and readable.
- Ensures consistent naming across all resources.
- Makes future maintenance easier.

Example:

Instead of writing:

metadata:
  name: {{ .Release.Name }}

inside every template, we simply write:

metadata:
  name: {{ include "users.fullname" . }}

Official Documentation:
https://helm.sh/docs/chart_template_guide/named_templates/

------------------------------------------------------------------------------
*/}}

{{/*
Generate the Helm chart name.

Example:

users

This value comes from Chart.yaml.
*/}}
{{- define "users.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/*
Generate the fully qualified resource name.

Helm Release Example:

helm install users ./charts/users

Result:

users

If installed as:

helm install identity-service ./charts/users

Result:

identity-service

Every Kubernetes resource created by this chart
will share this name.

Examples:

Deployment
Service
ConfigMap
Secret
ServiceAccount

*/}}
{{- define "users.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{/*
Generate common Kubernetes labels.

These labels are applied to every resource created by this chart.

They help Kubernetes, Helm and developers identify resources.

Example:

kubectl get all \
-l app.kubernetes.io/name=users

*/}}
{{- define "users.labels" -}}
app.kubernetes.io/name: {{ include "users.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/*
Generate selector labels.

Selectors are used by Kubernetes Services
to locate the correct Pods.

These labels MUST remain stable.

Changing selector labels after deployment
can break communication between Services
and Pods.

*/}}
{{- define "users.selectorLabels" -}}
app.kubernetes.io/name: {{ include "users.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Generate the ServiceAccount name.

If serviceAccount.create is enabled,
the ServiceAccount will use the Helm release name.

Otherwise, Kubernetes will use the namespace's
default ServiceAccount.

*/}}
{{- define "users.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ include "users.fullname" . }}
{{- else -}}
default
{{- end -}}
{{- end -}}
