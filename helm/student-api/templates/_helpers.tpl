{{- define "student-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "student-api.fullname" -}}
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

{{- define "student-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "student-api.labels" -}}
helm.sh/chart: {{ include "student-api.chart" . }}
{{ include "student-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/component: api
app.kubernetes.io/part-of: student-api
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "student-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "student-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "student-api.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}

{{/*
Secret holding DATABASE_URL — either the one ESO creates or an existing one.
*/}}
{{- define "student-api.dbSecretName" -}}
{{- if .Values.externalSecrets.enabled }}
{{- default (printf "%s-db-url" (include "student-api.fullname" .)) .Values.externalSecrets.databaseUrl.targetSecretName }}
{{- else if .Values.existingSecret.name }}
{{- .Values.existingSecret.name }}
{{- else }}
{{- fail "student-api: set externalSecrets.enabled=true or existingSecret.name — the chart never holds DATABASE_URL itself" }}
{{- end }}
{{- end }}

{{- define "student-api.dbSecretKey" -}}
{{- if .Values.externalSecrets.enabled }}
{{- "DATABASE_URL" }}
{{- else }}
{{- .Values.existingSecret.key }}
{{- end }}
{{- end }}

{{- define "student-api.registrySecretName" -}}
{{- default (printf "%s-registry" (include "student-api.fullname" .)) .Values.imagePullSecret.targetSecretName }}
{{- end }}
