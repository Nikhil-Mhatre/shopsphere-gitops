{{- define "user-service.fullname" -}}
{{ .Release.Name }}
{{- end }}

{{- define "user-service.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "user-service.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "user-service.serviceAccountName" -}}
{{ .Release.Name }}
{{- end }}
