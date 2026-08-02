{{/*
------------------------------------------------------------------------------
PostgreSQL Helm Chart Helper Templates
------------------------------------------------------------------------------

This file contains reusable helper functions used throughout the Helm chart.

Why use helpers?

Instead of repeating the same template logic in every Kubernetes manifest,
we define it once here and reuse it everywhere.

For example:

Instead of writing:

metadata:
  name: {{ .Release.Name }}-postgres

inside every YAML file,

we simply write:

metadata:
  name: {{ include "postgres.fullname" . }}

This keeps templates:
- Smaller
- Easier to read
- Easier to maintain
- Consistent across the chart

Official Documentation:
https://helm.sh/docs/chart_template_guide/named_templates/

------------------------------------------------------------------------------
*/}}

{{/*
Generate the Helm chart name.

Example:

postgres

*/}}
{{- define "postgres.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/*
Generate the fully qualified resource name.

Helm Release Name:
------------------

If the release name is:

user-postgres

The generated resource name becomes:

user-postgres

This ensures every Kubernetes resource created by this chart
shares the same predictable name.

Example resources:

Service
PersistentVolumeClaim
StatefulSet
Secret

will all be named:

user-postgres

*/}}
{{- define "postgres.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{/*
Common Kubernetes labels.

These labels are applied to every resource created by this chart.

They make it easier to:

- Search resources
- Group resources
- Debug deployments

Example:

kubectl get all -l app.kubernetes.io/name=postgres

*/}}
{{- define "postgres.labels" -}}
app.kubernetes.io/name: {{ include "postgres.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/*
Selector labels.

Selectors are used by Kubernetes Services
to find the correct Pods.

These labels MUST remain stable.

Changing them after deployment
can break Service-to-Pod communication.

*/}}
{{- define "postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgres.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
