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
            sh """
              /kaniko/executor --dockerfile `pwd`/Dockerfile \
                  --context `pwd` \
                  --custom-platform=linux/arm64,linux/amd64 \
                  --destination="harbor.cib.de/dev/cibseven:1.0" \
                  --destination="harbor.cib.de/dev/cibseven:latest"
            """
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
            sh """
              /kaniko/executor --dockerfile `pwd`/Dockerfile \
                  --context `pwd` \
                  --custom-platform=linux/arm64,linux/amd64 \
                  --destination="docker.io/cibseven/cibseven:1.0" \
                  --destination="docker.io/cibseven/cibseven:latest"
            """
          }
        }
      }
    }

  }
}
