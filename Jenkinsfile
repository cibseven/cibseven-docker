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
    ),
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
          withCredentials([usernamePassword(credentialsId: 'credential-nexus-usernamepassword', passwordVariable: 'PASS', usernameVariable: 'USER')]) {
            script {
              sh """
                /kaniko/executor --dockerfile `pwd`/Dockerfile \
                    --context `pwd` \
                    --build-arg USER="${USER}" \
                    --build-arg PASSWORD=${PASS} \
                    --destination=harbor.cib.de/dev/cibseven:1.0
              """
            }
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
          withCredentials([usernamePassword(credentialsId: 'credential-dockerhub-cibseven-usernamepassword', passwordVariable: 'PASS', usernameVariable: 'USER')]) {
            script {
              sh """
                /kaniko/executor --dockerfile `pwd`/Dockerfile \
                    --context `pwd` \
                    --build-arg USER="${USER}" \
                    --build-arg PASSWORD=${PASS} \
                    --destination=cibseven/cibseven:1.0
              """
            }
          }
        }
      }
    }

  }
}
