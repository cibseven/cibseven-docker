ARG VERSION=3.0.0
ARG JAVA=21
ARG OPENTELEMETRY_AGENT_VERSION=2.28.1

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
        libcrypto3 \
        libssl3 \
        zlib=1.3.2-r1

COPY settings.xml download.sh cibseven-run.sh cibseven-run4.sh cibseven-tomcat.sh cibseven-wildfly.sh  /tmp/

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
# AI Agent connector toggle. The ai-agent connector ships active-by-default in
# the Tomcat distribution. Set AI_AGENT_ENABLED=false to deactivate it at startup.
ENV AI_AGENT_ENABLED=true
ENV JAVA_OPTS=""
ENV WILDFLY_MANAGEMENT_BLOCKING_TIMEOUT=600

# OpenTelemetry Java agent toggle (opt-in). When false (the default) the agent is
# NOT attached on Tomcat/WildFly, mirroring the pre-2.x JMX_PROMETHEUS=false default.
# Set OTEL_AGENT_ENABLED=true to load the agent and configure exporters via OTEL_* below.
# (The Spring Boot run/run4 distributions always load the agent via JAVA_OPTS.)
ENV OTEL_AGENT_ENABLED=false

# OpenTelemetry default exporter settings (all exporters disabled, user must configure)
# Note: The OTEL agent is loaded via server-specific variables (PREPEND_JAVA_OPTS for WildFly,
# CATALINA_OPTS for Tomcat) to avoid affecting CLI tools like jboss-cli.sh
ENV OTEL_SERVICE_NAME=cibseven \
    OTEL_JMX_CONFIG=/camunda/javaagent/jmx_config.yaml,/camunda/javaagent/jmx_custom_config.yaml \
    OTEL_JAVAAGENT_LOGGING=application \
    OTEL_LOG_LEVEL=error \
    OTEL_METRICS_EXPORTER=none \
    OTEL_LOGS_EXPORTER=none \
    OTEL_TRACES_EXPORTER=none \
    OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0 \
    OTEL_EXPORTER_PROMETHEUS_PORT=9464

EXPOSE 8080 8000 9464

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
        libcrypto3 \
        libssl3 \
        zlib=1.3.2-r1 \
    && curl -o /usr/local/bin/wait-for-it.sh \
      "https://raw.githubusercontent.com/vishnubob/wait-for-it/a454892f3c2ebbc22bd15e446415b8fcb7c1cfa4/wait-for-it.sh" \
    && chmod +x /usr/local/bin/wait-for-it.sh

RUN addgroup -g 1000 -S camunda && \
    adduser -u 1000 -S camunda -G camunda -h /camunda -s /bin/bash -D camunda
WORKDIR /camunda

RUN chgrp -R 0 /camunda && \
    chmod -R g=u /camunda

# CVE-2026-91403: eMudhra generated weak keys for some intermediate CAs. Do what OpenJDK
# 21.0.13.0.3 / 17.0.21.0.3 do: block the 16 compromised intermediates (blocked.certs, JDK-8395142)
# and stop trusting the eMudhra (emSign) roots and the Comodo AAA root that cross-signed them.
# Alpine builds the Java truststore from ca-certificates, which still ships emSign Root CA - G1,
# so deselect the roots in /etc/ca-certificates.conf (kept on package upgrades) and regenerate the
# system bundle and the Java truststore. The build fails if a root is left or a check goes wrong.
RUN set -eu; \
    sed -i -E 's/^[^#!].*(emsign|emudhra|comodo_aaa).*$/!&/I' /etc/ca-certificates.conf; \
    update-ca-certificates; \
    blocked="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")/lib/security/blocked.certs"; \
    grep -qx 'Algorithm=SHA-256' "$blocked"; \
    [ -z "$(tail -c1 "$blocked")" ] || echo >> "$blocked"; \
    for fp in \
        0164D7CEAE5BB909C272AF151FF44B1177AE9B47D9424B94F1D9558C30934D19 \
        42C4ACCD12C4F59597925E1A08A7A90102608543809308D50EC427E118BA1493 \
        432EC25F0D28DE9006D97BF752F17BBB2CD41F669933FCB072D9A1148D0261F3 \
        45A883F349AEDFD5F3A649B5498FFB121712BA8B448F3F2A91DBC5A766FCDDBE \
        4B2460A466F95FD40113BCDCCA2CEB29B3B093921DE45474DA7DF48874C630B1 \
        579480AEA166290BD3C643589E795FC0D0E54E86505D180F1DFF99EFD3199512 \
        5F1DED4DD590AF74631290CF073B122A2AAC6A1FA479778A0BD43579BD832699 \
        62B7F9868263F72F6911FC78CEAF72C1979158B7368BF648683BB2AA39B02E72 \
        7485B51C0ED192878FA1D2F948FB529AE1842CC5086C4B67F7BE5B2039DE9489 \
        84112972B8E59D14560AE7E7119654474AAD119990CF3722BFC1E3B91615E1FD \
        98B896625C0C230ADEEC3EB2CF6AAD5001ECF9156A68644E82374CE5833BC25B \
        9E39DE2881273ACC225A149C72BA3E0F51424963669AB633EE1DC7DF5DB067B4 \
        A496E23AC0CAB8155FC9B117B97EAE368EFCBB9041AEC8804D5A308D2D01C2D8 \
        CB6E15165AC802E9B3F993F16C25D41F4E81C21EBDE71AE1B012AC00BF9C7C3F \
        E7568FE6E12331F4FD7DE61DA4C7559D0F8EB192A218D4741A3BA75184333838 \
        FD9D5C2DBBD4995AB69B8D50C439D9527B00529199C2FD01B2174EB58F07021F; do \
      grep -qx "$fp" "$blocked" || echo "$fp" >> "$blocked"; \
      grep -qx "$fp" "$blocked"; \
    done; \
    keytool -list -v -cacerts -storepass changeit > /tmp/cacerts.txt; \
    keytool -printcert -file /etc/ssl/certs/ca-certificates.crt > /tmp/bundle.txt; \
    if [ "$(grep -c '^Alias name: ' /tmp/cacerts.txt)" -lt 50 ] \
        || grep -qiE 'emsign|emudhra|CN=AAA Certificate Services' /tmp/cacerts.txt /tmp/bundle.txt; then \
      echo 'ERROR: eMudhra/emSign or Comodo AAA CA still trusted (or truststore broken)' >&2; exit 1; \
    fi; \
    rm -f /tmp/cacerts.txt /tmp/bundle.txt

USER camunda

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["./cibseven.sh"]

COPY --chown=camunda:camunda --from=builder /camunda .

# --- Add JMX config files (ensure these are present in your build context) ---
COPY --chown=camunda:camunda opentelemetry/jmx_config.yaml /camunda/javaagent/jmx_config.yaml
COPY --chown=camunda:camunda opentelemetry/jmx_custom_config.yaml /camunda/javaagent/jmx_custom_config.yaml
