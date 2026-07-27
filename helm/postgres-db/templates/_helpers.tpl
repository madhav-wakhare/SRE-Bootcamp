{{- define "postgres-db.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "postgres-db.fullname" -}}
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

{{- define "postgres-db.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "postgres-db.labels" -}}
helm.sh/chart: {{ include "postgres-db.chart" . }}
{{ include "postgres-db.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/component: database
app.kubernetes.io/part-of: student-api
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "postgres-db.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgres-db.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "postgres-db.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}

{{/*
Name of the Secret holding POSTGRES_PASSWORD — either the one ESO creates or an
existing one supplied by the operator. Fails loudly when neither is configured,
because a Postgres pod without a password silently never becomes ready.
*/}}
{{- define "postgres-db.secretName" -}}
{{- if .Values.externalSecrets.enabled }}
{{- default (printf "%s-secret" (include "postgres-db.fullname" .)) .Values.externalSecrets.targetSecretName }}
{{- else if .Values.existingSecret.name }}
{{- .Values.existingSecret.name }}
{{- else }}
{{- fail "postgres-db: set externalSecrets.enabled=true or existingSecret.name — the chart never holds the password itself" }}
{{- end }}
{{- end }}

{{/*
Key inside that Secret.
*/}}
{{- define "postgres-db.secretKey" -}}
{{- if .Values.externalSecrets.enabled }}
{{- "POSTGRES_PASSWORD" }}
{{- else }}
{{- .Values.existingSecret.key }}
{{- end }}
{{- end }}
