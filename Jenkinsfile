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

  parameters {
    booleanParam(name: 'DEPLOY_ANY_BRANCH', defaultValue: false, description: 'Normally only the master branch is deployed to the Harbor registry (harbor.cib.de). Activate this option to allow for deploying from a non-master branch')
  }

  stages {
    stage('prepare workspace and checkout') {
      steps {
        printSettings()
      }
    }

    stage('build & push image') {
      when {
        anyOf {
          branch 'master'
          expression { params.DEPLOY_ANY_BRANCH }
        }
      }
      steps {
        container(Constants.KANIKO_CONTAINER) {
          withCredentials([usernamePassword(credentialsId: 'credential-nexus-usernamepassword', passwordVariable: 'PASS', usernameVariable: 'USER')]) {
            script {
              sh """
                /kaniko/executor --dockerfile `pwd`/Dockerfile \
                    --context `pwd`
              """
            }
          }
        }
      }
    }
  }
}
