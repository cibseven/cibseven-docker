ARG VERSION=2.2.0
ARG JAVA=17

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

ARG JMX_PROMETHEUS_VERSION=1.0.1

RUN apk add --no-cache \
        bash \
        ca-certificates \
        maven \
        tar \
        wget \
        xmlstarlet \
        zlib=1.3.2-r0

COPY settings.xml download.sh cibseven-run.sh cibseven-tomcat.sh cibseven-wildfly.sh wait-for-it.sh /tmp/

RUN /tmp/download.sh
COPY wait_for_it-lib.sh /camunda/


##### FINAL IMAGE #####

FROM alpine:3.23

# Re-declare to use in this stage (inherits the value from global)
ARG VERSION
ARG JAVA

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
ENV JMX_PROMETHEUS=false
ENV JMX_PROMETHEUS_CONF=/camunda/javaagent/prometheus-jmx.yml
ENV JMX_PROMETHEUS_PORT=9404

EXPOSE 8080 8000 9404

RUN apk add --no-cache \
        bash \
        ca-certificates \
        curl \
        openjdk${JAVA}-jre-headless \
        tzdata \
        tini \
        xmlstarlet \
        zlib=1.3.2-r0

COPY --from=builder /tmp/wait-for-it.sh /usr/local/bin/wait-for-it.sh
RUN chmod +x /usr/local/bin/wait-for-it.sh

RUN addgroup -g 1000 -S camunda && \
    adduser -u 1000 -S camunda -G camunda -h /camunda -s /bin/bash -D camunda
WORKDIR /camunda
USER camunda

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["./cibseven.sh"]

COPY --chown=camunda:camunda --from=builder /camunda .
