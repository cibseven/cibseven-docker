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
# 21.0.13.0.3 / 17.0.21.0.3 do: block the compromised intermediates in the JDK's blocked.certs
# (JDK-8395142: 16 certificates, 48 fingerprints including alternate encodings) and stop trusting
# the eMudhra (emSign) roots and the Comodo AAA root that cross-signed them (JDK-8395690).
# Alpine builds the Java truststore from ca-certificates, which still ships emSign Root CA - G1,
# so deselect the roots in /etc/ca-certificates.conf and regenerate the system bundle and the
# Java truststore. The build fails if a root is left or a check goes wrong.
RUN set -eu; \
    sed -i -E 's/^[^#!].*(emsign|emudhra|comodo_aaa).*$/!&/I' /etc/ca-certificates.conf; \
    update-ca-certificates; \
    java="$(command -v java)" || { echo 'ERROR: java not on PATH' >&2; exit 1; }; \
    blocked="$(dirname "$(dirname "$(readlink -f "$java")")")/lib/security/blocked.certs"; \
    grep -qx 'Algorithm=SHA-256' "$blocked" || { echo "ERROR: unexpected format of $blocked" >&2; exit 1; }; \
    [ -z "$(tail -c1 "$blocked")" ] || echo >> "$blocked"; \
    for fp in \
        0164D7CEAE5BB909C272AF151FF44B1177AE9B47D9424B94F1D9558C30934D19 \
        10E7E5BFDB55CFB78D0C21366654046182087A1960C079682513795665AA0C6B \
        169A0523C5E071AA4E298286DBD4EE0E40C8C06ABB6B0C077D132F001FA19240 \
        21182E577E5106B669322ABE6086FFF6B101E8C83FD2D01DC32D854961AAC832 \
        33C1BCDC6DA52DF950B3B14121127DA1955F7F31F828497A7608986EB2DDCC09 \
        37E866582D43C35D7C17D47794B974F291B3047B868DC123382477F7A08AEFA8 \
        3B88E4B77FC53C45CA216700E39FC0EA7621A0A40FCB268215082E35D2BD5829 \
        3C5456D4219BA2372273867FAC9A07104600391E96C7FDCDE3B4420C0F1F69BF \
        42C4ACCD12C4F59597925E1A08A7A90102608543809308D50EC427E118BA1493 \
        432EC25F0D28DE9006D97BF752F17BBB2CD41F669933FCB072D9A1148D0261F3 \
        45A883F349AEDFD5F3A649B5498FFB121712BA8B448F3F2A91DBC5A766FCDDBE \
        4B2460A466F95FD40113BCDCCA2CEB29B3B093921DE45474DA7DF48874C630B1 \
        4DED6F955374E40B8558A611A9719B2AB69AA6852AC50966EDC4B07DE4D4277C \
        50E71B08B9AC407B93D50EE90100CB6B6B41C956DC7AA86C5BAA38AE713CFD6A \
        558EC6CA13DA9B800FEDC9ACC3C18CA98BB19768F1309B60B5BB89793B3481CB \
        579480AEA166290BD3C643589E795FC0D0E54E86505D180F1DFF99EFD3199512 \
        59CC5FD35A737B84682EDA26AD23F5ADE8AA847D5BEB3B38AB6CD62347925A66 \
        5D8FC3ECDDB4DDB243AEE5C306BCFDE670ADF2D66B193DD3AA2D6B2FB91869BE \
        5F1DED4DD590AF74631290CF073B122A2AAC6A1FA479778A0BD43579BD832699 \
        62B7F9868263F72F6911FC78CEAF72C1979158B7368BF648683BB2AA39B02E72 \
        7485B51C0ED192878FA1D2F948FB529AE1842CC5086C4B67F7BE5B2039DE9489 \
        75D8853BE99C87678E6C7BF9F684B31454D81DEB1C7F37B9FBC026A268337536 \
        7BA62FEC54E9D040556FCA70A6A88F03761C178FA1F7CB8390A73076849F55A2 \
        84112972B8E59D14560AE7E7119654474AAD119990CF3722BFC1E3B91615E1FD \
        8F580C6E34CEE7EE57B93BA9C0AC5FAEDD7BF3085F5EE9C6C0175A2555B111D0 \
        8FED925362F62FFF90DD835BE6ADC32B02DEC8DF5E82D83E512F1C977D066E82 \
        912A48745BFF2F14D1798B27858613DE1C0EB03C2BDE630AFD0DDD5251E1EBE1 \
        98B896625C0C230ADEEC3EB2CF6AAD5001ECF9156A68644E82374CE5833BC25B \
        9E39DE2881273ACC225A149C72BA3E0F51424963669AB633EE1DC7DF5DB067B4 \
        9E7617035CFF537C837E078A7CDC7FD9EB77BCE7DDF3DC6DBD5C50AAFC1F1FA7 \
        A0ED2032C5249EE1A653F1F88005D9E779E385DF533B5C521137CEE5176CD7FC \
        A104B1314DF8E02F7DE27DDC287D0961D6E6824AD4DAFC3D11064F24C1B653D5 \
        A4328E058C867AF9CA8D468C388B72C250CE84BDB6BAF7F8C47C9A0B1CB35EEC \
        A496E23AC0CAB8155FC9B117B97EAE368EFCBB9041AEC8804D5A308D2D01C2D8 \
        A4B72DBD37256324B557B9176F8CBA4310DDFFBCC4609977E2463F3504A716C8 \
        A61FE79B019062DD3C6420BC20EAF64702CC1063C546A084DD0A0BCB915A14A9 \
        AB7292F82267333031F512379FDBADA949DFA49D3C046CC8FA7F34117C342986 \
        B7121039CAF13E03E52507F42DB56FA802FF119DA7591ABA8A2E842133DB7C9C \
        B75104427B6A5BE55033AF50DC0FE3102181BE130E761D487A4E8178C93317DD \
        C5F1531C6331659C75A6411A088A65DAD7518FD91F57B64537A651B6DCD76AE0 \
        C65CBC98295549BA940494A6214B9706E7115E64F3FE269412C5B48AEACB2222 \
        C93F7B1EEF27CFD0F227DFE3F057D63833533890B7230B1821A424BD40848E33 \
        CB6E15165AC802E9B3F993F16C25D41F4E81C21EBDE71AE1B012AC00BF9C7C3F \
        CD740652E552D93EE64D7C9D1CC25228E466895889CEE25A11C962AB09906978 \
        D8A50FA0068E9558E6C3BEE18CDB03B7EECBC3C56C1B2336B98AEE11644994B8 \
        E7568FE6E12331F4FD7DE61DA4C7559D0F8EB192A218D4741A3BA75184333838 \
        EF34030C01B13BF42B534072DCC3C75B13C009DC9241119ADA39E2C15E2AFD2E \
        FD9D5C2DBBD4995AB69B8D50C439D9527B00529199C2FD01B2174EB58F07021F; do \
      grep -qx "$fp" "$blocked" || echo "$fp" >> "$blocked"; \
      grep -qx "$fp" "$blocked"; \
    done; \
    keytool -J-XX:-UsePerfData -J-Duser.language=en -list -v -cacerts -storepass changeit > /tmp/cacerts.txt; \
    keytool -J-XX:-UsePerfData -J-Duser.language=en -printcert -file /etc/ssl/certs/ca-certificates.crt > /tmp/bundle.txt; \
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
