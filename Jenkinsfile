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

  stages {
    stage('prepare workspace and checkout') {
      steps {
        printSettings()
      }
    }

    stage('build & push image') {
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
  }
}
