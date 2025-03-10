#!groovy

@Library('cib-pipeline-library') _

import de.cib.pipeline.library.Constants
import de.cib.pipeline.library.kubernetes.BuildPodCreator
import de.cib.pipeline.library.MavenArtifact

def opentelemetryAgentVersion = ""
def cibsevenVersion = ""

pipeline {
  agent {
    kubernetes {
      yaml BuildPodCreator.cibStandardPod()
          .withMavenJdk17Container()
          .withKanikoContainer()
          .asYaml()
      defaultContainer Constants.MAVEN_JDK_17_CONTAINER
    }
  }

  options {
    disableConcurrentBuilds()
  }

  // Parameter that can be changed in the Jenkins UI
  parameters {
    booleanParam(
      name: 'DEPLOY_HARBOR_CIB_DE',
      defaultValue: false,
      description: 'Deploy to https://harbor.cib.de (snapshots, amd64 only)'
    )
    booleanParam(
      name: 'DEPLOY_DOCKER_HUB',
      defaultValue: false,
      description: 'Deploy to https://hub.docker.com (public released versions, amd64 only). Please, use GitHub Actions, to deploy all possible platforms. Patch versions will not be deployed into hub.docker.com.'
    )
  }

  stages {
    stage('prepare workspace and checkout') {
      steps {
        printSettings()
        script {
          cibsevenVersion = sh(
            script: 'grep VERSION= Dockerfile | head -n1 | cut -d = -f 2',
            returnStdout: true
          ).trim()
          echo "CIB seven version ${cibsevenVersion}"
        }
      }
    }

    stage('harbor.cib.de') {
      when {
        expression { params.DEPLOY_HARBOR_CIB_DE == true }
      }
      steps {
        container(Constants.KANIKO_CONTAINER) {
          script {
            pushImage("harbor.cib.de/dev", "linux/amd64", cibsevenVersion)
            // pushImage("harbor.cib.de/dev", "linux/arm64", cibsevenVersion)
          }
        }
      }
    }

    stage('hub.docker.com') {
      when {
        allOf {
          expression { params.DEPLOY_DOCKER_HUB == true }
          expression { isPatchVersion(cibsevenVersion) == false }
        }
      }
      steps {
        container(Constants.KANIKO_CONTAINER) {
          script {
            pushImage("docker.io/cibseven", "linux/amd64", cibsevenVersion)
            // pushImage("docker.io/cibseven", "linux/arm64", cibsevenVersion)
          }
        }
      }
    }

  }
}

def pushImage(String destination, String platform, String cibsevenVersion) {
  withMaven(options: []) {
    def prefix = ""
    if (platform == "linux/arm64") {
      prefix = "arm64-"
    }

    def deployLatest = !isPatchVersion(cibsevenVersion)
    if (deployLatest) {
      sh """
        /kaniko/executor --dockerfile `pwd`/Dockerfile \
            --context `pwd` \
            --custom-platform=${platform} \
            --destination="${destination}/cibseven:${prefix}${cibsevenVersion}" \
            --destination="${destination}/cibseven:${prefix}latest"
      """
    }
    else {
      sh """
        /kaniko/executor --dockerfile `pwd`/Dockerfile \
            --context `pwd` \
            --custom-platform=${platform} \
            --destination="${destination}/cibseven:${prefix}${cibsevenVersion}"
      """
    }
  }
}

// - "1.2.0" -> no
// - "1.2.0-SNAPSHOT" -> no
// - "1.2.3" -> yes
// - "1.2.3-SNAPSHOT" -> yes
// - "7.22.0-cibseven" -> no
// - "7.22.1-cibseven" -> yes
def isPatchVersion(cibsevenVersion) {
    List version = cibsevenVersion.tokenize('.')
    if (version.size() < 3) {
        return false
    }
    return version[2].tokenize('-')[0] != "0"
}
