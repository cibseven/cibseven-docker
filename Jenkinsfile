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

    stage('download maven artifacts') {
      when {
        anyOf {
          branch 'master'
          expression { params.DEPLOY_ANY_BRANCH }
        }
      }
      steps {
        script {
          def uploadDir = "./opentelemetry/"
          opentelemetryAgentVersion = "2.8.0"
          downloadMavenArtifact(new MavenArtifact("io.opentelemetry.javaagent", "opentelemetry-javaagent", "${opentelemetryAgentVersion}", "jar", uploadDir, ""))
        }
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
          script {
            // TODO: move into Dockerfile
            def imageVersion = '1.0'
            sh """
              /kaniko/executor --dockerfile `pwd`/Dockerfile \
                  --context `pwd` \
                  --build-arg arg_version=${imageVersion} \
                  --build-arg arg_opentelemetry_agent_version=${opentelemetryAgentVersion} \
                  --destination=harbor.cib.de/dev/cib-seven:${imageVersion}
            """
          }
        }
      }
    }
  }
}
