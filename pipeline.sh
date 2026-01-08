#!/bin/bash -ex

if [ -z "$SNAPSHOT" ]; then
  SNAPSHOT_ARGUMENT=""
else
  SNAPSHOT_ARGUMENT="--build-arg SNAPSHOT=${SNAPSHOT}"
fi

if [ -z "$VERSION" ]; then
  VERSION_ARGUMENT=""
else
  VERSION_ARGUMENT="--build-arg VERSION=${VERSION}"
fi

if [ -z "$JAVA" ]; then
  JAVA_ARGUMENT=""
else
  JAVA_ARGUMENT="--build-arg JAVA=${JAVA}"
fi

REPO=docker.io
IMAGE=cibseven/cibseven
if [ "${JAVA:-17}" = "21" ]; then
    IMAGE_NAME=${REPO}/${IMAGE}:java21-${DISTRO}-${PLATFORM}
else
    IMAGE_NAME=${REPO}/${IMAGE}:${DISTRO}-${PLATFORM}
fi

docker buildx build .                         \
    -t "${IMAGE_NAME}"                        \
    --platform linux/${PLATFORM}              \
    --build-arg DISTRO=${DISTRO}              \
    --build-arg USER=${NEXUS_USER}            \
    --build-arg PASSWORD=${NEXUS_PASS}        \
    ${VERSION_ARGUMENT}                       \
    ${SNAPSHOT_ARGUMENT}                      \
    ${JAVA_ARGUMENT}                          \
    --cache-to type=gha,scope="$GITHUB_REF_NAME-$DISTRO-java${JAVA:-17}-image" \
    --cache-from type=gha,scope="$GITHUB_REF_NAME-$DISTRO-java${JAVA:-17}-image" \
    --load

docker inspect "${IMAGE_NAME}" | grep "Architecture" -A2
