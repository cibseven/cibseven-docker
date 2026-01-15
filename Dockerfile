ARG VERSION=2.2.0
ARG JAVA=17
ARG OPENTELEMETRY_AGENT_VERSION=2.23.0

FROM alpine:3.23 as builder

# Re-declare to use in this stage (inherits the value from global)
ARG VERSION
ARG DISTRO=tomcat
ARG SNAPSHOT=true

ARG USER
ARG PASSWORD

ARG MAVEN_PROXY_HOST
ARG MAVEN_PROXY_PORT
ARG MAVEN_PROXY_USER
ARG MAVEN_PROXY_PASSWORD

ARG POSTGRESQL_VERSION
ARG MYSQL_VERSION


# --- OpenTelemetry Java Agent version argument ---
# Re-declare to use in this stage (inherits the value from global)
ARG OPENTELEMETRY_AGENT_VERSION

RUN apk add --no-cache \
        bash \
        ca-certificates \
        maven \
        tar \
        wget \
        xmlstarlet \
        c-ares=1.34.6-r0

COPY settings.xml download.sh cibseven-run.sh cibseven-tomcat.sh cibseven-wildfly.sh  /tmp/

RUN /tmp/download.sh
COPY wait_for_it-lib.sh /camunda/

##### FINAL IMAGE #####

FROM alpine:3.23

# Re-declare to use in this stage (inherits the value from global)
ARG VERSION
ARG JAVA
ARG OPENTELEMETRY_AGENT_VERSION
ENV OPENTELEMETRY_AGENT_VERSION=${OPENTELEMETRY_AGENT_VERSION}

ENV DB_DRIVER=
ENV DB_URL=
ENV DB_USERNAME=
ENV DB_PASSWORD=
ENV DB_CONN_MAXACTIVE=20
ENV DB_CONN_MINIDLE=5
ENV DB_CONN_MAXIDLE=20
ENV DB_VALIDATE_ON_BORROW=false
ENV DB_VALIDATION_QUERY="SELECT 1"
ENV SKIP_DB_CONFIG=
ENV WAIT_FOR=
ENV WAIT_FOR_TIMEOUT=30
ENV TZ=UTC
ENV DEBUG=false
ENV JAVA_OPTS=""

# --- Use OpenTelemetry agent by default ---
#ENV JAVA_TOOL_OPTIONS="-javaagent:/camunda/javaagent/opentelemetry-javaagent-${OPENTELEMETRY_AGENT_VERSION}.jar"


# OpenTelemetry default exporter settings (all exporters disabled, user must configure)
ENV OTEL_SERVICE_NAME=cibseven \
    OTEL_JMX_CONFIG=/camunda/javaagent/jmx_config.yaml,/camunda/javaagent/jmx_custom_config.yaml \
    OTEL_METRICS_EXPORTER=none \
    OTEL_LOGS_EXPORTER=none \
    OTEL_TRACES_EXPORTER=none \
    OTEL_EXPORTER_PROMETHEUS_PORT=9464

EXPOSE 8080 8000 9404 9464

# Downgrading wait-for-it is necessary until this PR is merged
# https://github.com/vishnubob/wait-for-it/pull/68
RUN apk add --no-cache \
        bash \
        ca-certificates \
        curl \
        openjdk${JAVA}-jre-headless \
        tzdata \
        tini \
        xmlstarlet \
        c-ares=1.34.6-r0 \
    && curl -o /usr/local/bin/wait-for-it.sh \
      "https://raw.githubusercontent.com/vishnubob/wait-for-it/a454892f3c2ebbc22bd15e446415b8fcb7c1cfa4/wait-for-it.sh" \
    && chmod +x /usr/local/bin/wait-for-it.sh

RUN addgroup -g 1000 -S camunda && \
    adduser -u 1000 -S camunda -G camunda -h /camunda -s /bin/bash -D camunda
WORKDIR /camunda
USER camunda

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["./cibseven.sh"]

COPY --chown=camunda:camunda --from=builder /camunda .

# --- Add JMX config files (ensure these are present in your build context) ---
COPY opentelemetry/jmx_config.yaml /camunda/javaagent/jmx_config.yaml
COPY opentelemetry/jmx_custom_config.yaml /camunda/javaagent/jmx_custom_config.yaml
