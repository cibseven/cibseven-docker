#!/bin/bash -eux

VERSION=${VERSION:-$(grep VERSION= Dockerfile | head -n1 | cut -d = -f 2)}
DISTRO=${DISTRO:-$(grep DISTRO= Dockerfile | cut -d = -f 2)}
SNAPSHOT=${SNAPSHOT:-$(grep SNAPSHOT= Dockerfile | cut -d = -f 2)}
JAVA=${JAVA:-17}
PLATFORMS=${PLATFORMS:-linux/amd64}
NEXUS_USER=${NEXUS_USER:-}
NEXUS_PASS=${NEXUS_PASS:-}

IMAGE=cibseven/cibseven

function build_and_push {
    local tags=("$@")
    printf -v tag_arguments -- "--tag $IMAGE:%s " "${tags[@]}"
    docker buildx build .                         \
        $tag_arguments                            \
        --build-arg DISTRO=${DISTRO}              \
        --build-arg JAVA=${JAVA}                  \
        --build-arg USER=${NEXUS_USER}            \
        --build-arg PASSWORD=${NEXUS_PASS}        \
        --cache-from type=gha,scope="$GITHUB_REF_NAME-$DISTRO-java${JAVA}-image" \
        --platform $PLATFORMS \
        --push

      echo "Tags released:" >> $GITHUB_STEP_SUMMARY
      printf -- "- $IMAGE:%s\n" "${tags[@]}" >> $GITHUB_STEP_SUMMARY
}

# check whether the image for distro was already released and exit in that case
if [ "${JAVA}" = "21" ]; then
    CHECK_TAG="java21-${DISTRO}-${VERSION}"
else
    CHECK_TAG="${DISTRO}-${VERSION}"
fi

if [ $(docker manifest inspect $IMAGE:${CHECK_TAG} > /dev/null ; echo $?) == '0' ]; then
    echo "Not pushing already released docker image: $IMAGE:${CHECK_TAG}"
    exit 0
fi

docker login -u "${DOCKER_HUB_USERNAME}" -p "${DOCKER_HUB_PASSWORD}"

tags=()

if [ "${SNAPSHOT}" = "true" ]; then
    if [ "${JAVA}" = "21" ]; then
        tags+=("java21-${DISTRO}-${VERSION}-SNAPSHOT")
        tags+=("java21-${DISTRO}-SNAPSHOT")
        
        if [ "${DISTRO}" = "tomcat" ]; then
            tags+=("java21-${VERSION}-SNAPSHOT")
            tags+=("java21-SNAPSHOT")
        fi
    else
        tags+=("${DISTRO}-${VERSION}-SNAPSHOT")
        tags+=("${DISTRO}-SNAPSHOT")

        if [ "${DISTRO}" = "tomcat" ]; then
            tags+=("${VERSION}-SNAPSHOT")
            tags+=("SNAPSHOT")
        fi
    fi
else
    if [ "${JAVA}" = "21" ]; then
        tags+=("java21-${DISTRO}-${VERSION}")
        if [ "${DISTRO}" = "tomcat" ]; then
            tags+=("java21-${VERSION}")
        fi
    else
        tags+=("${DISTRO}-${VERSION}")
        if [ "${DISTRO}" = "tomcat" ]; then
            tags+=("${VERSION}")
        fi
    fi
fi

# Latest Docker image is created and pushed just once when a new version is relased.
# Latest tag refers to the latest minor release of CIB seven.
# https://github.com/cibseven/cibseven-docker/blob/main/README.md#supported-tagsreleases
# The 1st condition matches only when the version branch is the same as the main branch.
if [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] && [ "${SNAPSHOT}" = "false" ]; then
    # tagging image as latest only from main branch
    if [ "${JAVA}" = "21" ]; then
        tags+=("java21-${DISTRO}-latest")
        tags+=("java21-${DISTRO}")
        if [ "${DISTRO}" = "tomcat" ]; then
            tags+=("java21-latest")
        fi
    else
        tags+=("${DISTRO}-latest")
        tags+=("${DISTRO}")
        if [ "${DISTRO}" = "tomcat" ]; then
            tags+=("latest")
        fi
    fi
fi

build_and_push "${tags[@]}"
