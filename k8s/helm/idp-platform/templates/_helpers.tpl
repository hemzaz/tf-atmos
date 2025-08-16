{{/*
Expand the name of the chart.
*/}}
{{- define "idp-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "idp-platform.fullname" -}}
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
{{- define "idp-platform.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "idp-platform.labels" -}}
helm.sh/chart: {{ include "idp-platform.chart" . }}
{{ include "idp-platform.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: idp-platform
{{- end }}

{{/*
Selector labels
*/}}
{{- define "idp-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "idp-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "idp-platform.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "idp-platform.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate database connection string for PostgreSQL
*/}}
{{- define "idp-platform.postgresql.connectionString" -}}
{{- if .Values.postgresql.enabled }}
postgresql://{{ .Values.postgresql.auth.username }}:$(POSTGRES_PASSWORD)@{{ include "idp-platform.fullname" . }}-postgresql:{{ .Values.postgresql.service.port }}/{{ .Values.postgresql.auth.database }}
{{- else }}
{{ .Values.externalDatabase.connectionString }}
{{- end }}
{{- end }}

{{/*
Generate Redis connection string
*/}}
{{- define "idp-platform.redis.connectionString" -}}
{{- if .Values.redis.enabled }}
{{- if .Values.redis.auth.enabled }}
redis://:$(REDIS_PASSWORD)@{{ include "idp-platform.fullname" . }}-redis:{{ .Values.redis.service.port }}
{{- else }}
redis://{{ include "idp-platform.fullname" . }}-redis:{{ .Values.redis.service.port }}
{{- end }}
{{- else }}
{{ .Values.externalRedis.connectionString }}
{{- end }}
{{- end }}

{{/*
Common pod annotations
*/}}
{{- define "idp-platform.podAnnotations" -}}
prometheus.io/scrape: "true"
{{- if .Values.global.podAnnotations }}
{{- toYaml .Values.global.podAnnotations }}
{{- end }}
{{- end }}

{{/*
Security context for containers
*/}}
{{- define "idp-platform.containerSecurityContext" -}}
allowPrivilegeEscalation: false
capabilities:
  drop:
    - ALL
readOnlyRootFilesystem: true
runAsNonRoot: true
runAsUser: 1001
runAsGroup: 1001
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{/*
Generate certificate secret name
*/}}
{{- define "idp-platform.certificateSecretName" -}}
{{- if .Values.ingress.tls }}
{{- .Values.ingress.tls.secretName }}
{{- else }}
{{ include "idp-platform.fullname" . }}-tls
{{- end }}
{{- end }}

{{/*
Validate required values
*/}}
{{- define "idp-platform.validateValues" -}}
{{- if and .Values.backstage.enabled (not .Values.postgresql.enabled) (not .Values.externalDatabase.connectionString) }}
{{- fail "Either postgresql.enabled must be true or externalDatabase.connectionString must be provided when backstage is enabled" }}
{{- end }}
{{- if and .Values.platformApi.enabled (not .Values.redis.enabled) (not .Values.externalRedis.connectionString) }}
{{- fail "Either redis.enabled must be true or externalRedis.connectionString must be provided when platformApi is enabled" }}
{{- end }}
{{- end }}

{{/*
Generate environment-specific configuration
*/}}
{{- define "idp-platform.environmentConfig" -}}
{{- if eq .Values.global.environment "development" }}
development: true
debug: true
{{- else if eq .Values.global.environment "staging" }}
development: false
debug: false
staging: true
{{- else }}
development: false
debug: false
production: true
{{- end }}
{{- end }}

{{/*
Generate resource limits based on environment
*/}}
{{- define "idp-platform.resourceLimits" -}}
{{- if eq .Values.global.environment "development" }}
requests:
  memory: "128Mi"
  cpu: "100m"
limits:
  memory: "512Mi"
  cpu: "500m"
{{- else if eq .Values.global.environment "staging" }}
requests:
  memory: "256Mi"
  cpu: "200m"
limits:
  memory: "1Gi"
  cpu: "1000m"
{{- else }}
requests:
  memory: "512Mi"
  cpu: "250m"
limits:
  memory: "2Gi"
  cpu: "1000m"
{{- end }}
{{- end }}

{{/*
Generate monitoring configuration
*/}}
{{- define "idp-platform.monitoringConfig" -}}
{{- if .Values.monitoring.prometheus.enabled }}
prometheus:
  enabled: true
  scrapeInterval: 30s
  evaluationInterval: 30s
{{- end }}
{{- if .Values.monitoring.grafana.enabled }}
grafana:
  enabled: true
  dashboardsConfigMaps:
    - name: {{ include "idp-platform.fullname" . }}-grafana-dashboards
{{- end }}
{{- if .Values.monitoring.jaeger.enabled }}
tracing:
  enabled: true
  jaeger:
    endpoint: http://{{ include "idp-platform.fullname" . }}-jaeger-collector:14268/api/traces
{{- end }}
{{- end }}