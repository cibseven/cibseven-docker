#!groovy

@Library('cib-pipeline-library') _

import de.cib.pipeline.library.Constants
import de.cib.pipeline.library.kubernetes.BuildPodCreator
import de.cib.pipeline.library.MavenArtifact

def opentelemetryAgentVersion = ""

pipeline {
  agent {
    kubernetes {
      yaml BuildPodCreator.cibStandardPod()
          .withMavenJdk11Container()
          .withKanikoContainer()
          .asYaml()
      defaultContainer Constants.MAVEN_JDK_11_CONTAINER
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
      description: 'Deploy to https://harbor.cib.de (snapshots)'
    )
    booleanParam(
      name: 'DEPLOY_DOCKER_HUB',
      defaultValue: false,
      description: 'Deploy to https://hub.docker.com (public released versions)'
    )
  }

  stages {
    stage('prepare workspace and checkout') {
      steps {
        printSettings()
      }
    }

    stage('harbor.cib.de') {
      when {
        expression { params.DEPLOY_HARBOR_CIB_DE == true }
      }
      steps {
        container(Constants.KANIKO_CONTAINER) {
          script {
            pushImage("harbor.cib.de", "linux/amd64")
            pushImage("harbor.cib.de", "linux/arm64")
          }
        }
      }
    }

    stage('hub.docker.com') {
      when {
        expression { params.DEPLOY_DOCKER_HUB == true }
      }
      steps {
        container(Constants.KANIKO_CONTAINER) {
          script {
            pushImage("docker.io", "linux/amd64")
            pushImage("docker.io", "linux/arm64")
          }
        }
      }
    }

  }
}

def pushImage(String destination, String platform) {
  def prefix = ""
  if (platform == "linux/arm64") {
    prefix = "arm64-"
  }

  sh """
    /kaniko/executor --dockerfile `pwd`/Dockerfile \
        --context `pwd` \
        --custom-platform={$platform} \
        --destination="{$destination}/cibseven/cibseven:${prefix}1.0" \
        --destination="{$destination}/cibseven/cibseven:${prefix}latest"
  """
}
