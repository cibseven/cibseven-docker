#!groovy

@Library('cib-pipeline-library') _

import de.cib.pipeline.library.Constants
import de.cib.pipeline.library.kubernetes.BuildPodCreator
import de.cib.pipeline.library.MavenArtifact

def DOCKER_REGISTRY = "harbor.cib.de/dev"
def DOCKER_PLATFORM = "linux/amd64"
def VERSION = ""
def SNAPSHOT = true

def buildPodConfig = [
    (Constants.KANIKO_CONTAINER): [
        resources: [
            cpu: '2',
            memory: '6Gi',
            ephemeralStorage: '8Gi'
        ]
    ]
]

pipeline {
  agent {
    kubernetes {
      yaml BuildPodCreator.fromScratch(this, buildPodConfig)
          .withMavenJdk17Container()
          .withKanikoContainer()
          .asYaml()
      defaultContainer Constants.MAVEN_JDK_17_CONTAINER
    }
  }

  options {
    disableConcurrentBuilds()
  }

  parameters {

    booleanParam(
      name: 'DEPLOY_HARBOR',
      defaultValue: false,
      description: "🚀 Deployment Target\n└─ Deploy snapshots to https://harbor.cib.de (amd64 only)"
    )

    booleanParam(
      name: 'DEPLOY_DOCKERHUB',
      defaultValue: false,
      description: "└─ Deploy public release versions to https://hub.docker.com (amd64 only). Prefer GitHub Actions for multi-platform images. Patch versions are not deployed to Docker Hub."
    )

    choice(
      name: 'DISTRO_BUILD',
      choices: ['CUSTOM', 'ALL'],
      description: '''🐳 Distribution Build Selection:
      • CUSTOM - Select individual distributions below (default, builds nothing if none selected)
      • ALL - Build all distributions'''
    )
    // Only used when DISTRO_BUILD = 'CUSTOM'
    booleanParam(name: 'BUILD_RUN', defaultValue: false, description: "  └─ Build 'run' distribution")
    booleanParam(name: 'BUILD_RUN4', defaultValue: false, description: "  └─ Build 'run4' distribution (Spring Boot 4)")
    booleanParam(name: 'BUILD_TOMCAT', defaultValue: false, description: "  └─ Build 'tomcat' distribution (tagged as default/latest)")
    booleanParam(name: 'BUILD_WILDFLY', defaultValue: false, description: "  └─ Build 'wildfly' distribution")

  }

  stages {
    stage('prepare workspace and checkout') {
      steps {
        printSettings()
        script {

          VERSION = sh(
            script: 'grep "^ARG VERSION=" Dockerfile | head -n1 | cut -d = -f 2',
            returnStdout: true
          ).trim()

          SNAPSHOT = sh(
            script: 'grep "^ARG SNAPSHOT=" Dockerfile | head -n1 | cut -d = -f 2',
            returnStdout: true
          ).trim().toBoolean()

          echo "Building CIB seven - Version: ${VERSION}, Snapshot: ${SNAPSHOT}"
        }
      }
    }

    stage('Deploy Docker Images') {
      stages {
        stage('Run Distribution') {
          when {
            expression {
              params.DISTRO_BUILD == 'ALL' || params.BUILD_RUN
            }
          }
          steps {
            container(Constants.KANIKO_CONTAINER) {
              script {
                pushImage(DOCKER_REGISTRY, DOCKER_PLATFORM, VERSION, 'run', false, SNAPSHOT)
              }
            }
          }
        }
        stage('Run4 Distribution') {
          when {
            expression {
              params.DISTRO_BUILD == 'ALL' || params.BUILD_RUN4
            }
          }
          steps {
            container(Constants.KANIKO_CONTAINER) {
              script {
                getBuildMatrix(VERSION, SNAPSHOT).each { config ->
                  pushImage(DOCKER_REGISTRY, DOCKER_PLATFORM, config.version, 'run4', false, config.isSnapshot)
                }
              }
            }
          }
        }
        stage('Tomcat Distribution') {
          when {
            expression {
              params.DISTRO_BUILD == 'ALL' || params.BUILD_TOMCAT
            }
          }
          steps {
            container(Constants.KANIKO_CONTAINER) {
              script {
                getBuildMatrix(VERSION, SNAPSHOT).each { config ->
                  pushImage(DOCKER_REGISTRY, DOCKER_PLATFORM, config.version, 'tomcat', true, config.isSnapshot)
                }
              }
            }
          }
        }
        stage('Wildfly Distribution') {
          when {
            expression {
              params.DISTRO_BUILD == 'ALL' || params.BUILD_WILDFLY
            }
          }
          steps {
            container(Constants.KANIKO_CONTAINER) {
              script {
                getBuildMatrix(VERSION, SNAPSHOT).each { config ->
                  pushImage(DOCKER_REGISTRY, DOCKER_PLATFORM, config.version, 'wildfly', false, config.isSnapshot)
                }
              }
            }
          }
        }
      }
    }
  }
}

// Returns list of version configurations to build
def getBuildMatrix(VERSION, SNAPSHOT) {
  def versions = []
  def baseVersions = [VERSION]
  def isSnapshot = SNAPSHOT
  baseVersions.each { baseVersion ->
    def fullVersion = baseVersion
    if (isSnapshot) {
      fullVersion = "${fullVersion}-SNAPSHOT"
    }
    versions.add([version: fullVersion, isSnapshot: isSnapshot])
  }
  return versions
}

def pushImage(String destination, String platform, String cibsevenVersion, String distro, boolean isDefault, boolean isSnapshot) {
  withMaven(options: []) {
    def prefix = ""
    if (platform == "linux/arm64") {
      prefix = "arm64-"
    }
    if (distro && distro != '') {
      prefix = prefix + "${distro}-"
    }

    // Deploy the 'latest' tag only for non-SNAPSHOT builds
    def deployLatest = !isSnapshot
    def distroArg = (distro && distro != '') ? "--build-arg DISTRO=\"${distro}\"" : ""

    // Extract base version (without -SNAPSHOT suffix) for Docker build arg
    def baseVersion = cibsevenVersion.replace('-SNAPSHOT', '')
    def versionArg = "--build-arg VERSION=\"${baseVersion}\""
    def snapshotArg = "--build-arg SNAPSHOT=${isSnapshot}"

    // Build destination tags
    def destinations = "--destination=\"${destination}/cibseven:${prefix}${cibsevenVersion}\""
    if (deployLatest) {
      destinations += " --destination=\"${destination}/cibseven:${prefix}latest\""
      // For default distribution (Tomcat), also tag without distro prefix
      if (isDefault) {
        destinations += " --destination=\"${destination}/cibseven:${cibsevenVersion}\""
        destinations += " --destination=\"${destination}/cibseven:latest\""
      }
    }

    // Clean Kaniko workspace BEFORE build to prevent layer accumulation
    sh """
      rm -rf /workspace/* /kaniko/.docker/* /kaniko/0 /kaniko/1 2>/dev/null || true
    """

    try {
      sh """
        /kaniko/executor --dockerfile `pwd`/Dockerfile \
            --context `pwd` \
            --custom-platform=${platform} \
            ${destinations} \
            --cache=false \
            --cleanup \
            ${distroArg} \
            ${versionArg} \
            ${snapshotArg}
      """
    } finally {
      // Clean up Kaniko's workspace to ensure clean state for next build
      sh """
        rm -rf /workspace/* /kaniko/.docker/* 2>/dev/null || true
      """
    }

  }
}

