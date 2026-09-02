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
      yaml BuildPodCreator.fromScratch(this)
          .withMavenJdk17Container()
          .withSyftContainer()
          .withKanikoContainer([
                        resources: [
                            cpu: '4',
                            memory: '16Gi',
                            ephemeralStorage: '14Gi'
                        ]
                    ]
          )
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
    choice(
      name: 'DISTRO',
      choices: ['tomcat', 'wildfly', 'run', 'run4'],
      description: 'Distribution to build and deploy'
    )
    booleanParam(
      name: 'ATTACH_SBOM_TO_ARTIFACTS',
      defaultValue: false,
      description: 'Attach generated image SBOMs as Jenkins build artifacts'
    )
    booleanParam(
      name: 'DEPLOY_WITHOUT_SBOM',
      defaultValue: false,
      description: 'Skip SBOM generation and OCI attachment entirely'
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
            // oci-1-1 confirmed working against harbor.cib.de
            pushImage("harbor.cib.de/dev", "linux/amd64", cibsevenVersion, params.DISTRO, "oci-1-1")
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
            // Docker Hub's OCI 1.1 referrers support is unconfirmed; skip SBOM deployment
            // there until a mode is verified and explicitly set.
            pushImage("docker.io/cibseven", "linux/amd64", cibsevenVersion, params.DISTRO, "none")
          }
        }
      }
    }

  }
}

def pushImage(String destination, String platform, String cibsevenVersion, String distro, String sbomDeployMode) {
  withMaven(options: []) {
    def prefix = ""
    if (platform == "linux/arm64") {
      prefix = "arm64-"
    }

    def imageTag = "${prefix}${distro}-${cibsevenVersion}"
    def sbomFile = "cibseven-${imageTag}.cdx.json"
    def primaryImageRef = "${destination}/cibseven:${imageTag}"
    def normalizedSbomDeployMode = normalizeSbomDeployMode(sbomDeployMode)
    def distroArg = "--build-arg DISTRO=\"${distro}\""

    def deployLatest = !isPatchVersion(cibsevenVersion)
    if (deployLatest) {
      sh """
        /kaniko/executor --dockerfile `pwd`/Dockerfile \
            --context `pwd` \
            --custom-platform=${platform} \
            --destination="${destination}/cibseven:${imageTag}" \
            --destination="${destination}/cibseven:${prefix}${distro}-latest" \
            ${distroArg}
      """
    }
    else {
      sh """
        /kaniko/executor --dockerfile `pwd`/Dockerfile \
            --context `pwd` \
            --custom-platform=${platform} \
            --destination="${destination}/cibseven:${imageTag}" \
            ${distroArg}
      """
    }

    def deploySbom = !params.DEPLOY_WITHOUT_SBOM && normalizedSbomDeployMode != "none"
    def attachSbom = params.ATTACH_SBOM_TO_ARTIFACTS
    if (attachSbom || deploySbom) {
      generateSbom(primaryImageRef, sbomFile)

      if (attachSbom) {
        archiveArtifacts artifacts: sbomFile, fingerprint: true
      }

      if (deploySbom) {
        deploySbomToRegistry(primaryImageRef, sbomFile, normalizedSbomDeployMode)
      }
    }
  }
}

// Treats any value other than "oci-1-1" or "legacy" as "none" (no SBOM deployment).
def normalizeSbomDeployMode(String sbomDeployMode) {
  return (sbomDeployMode == "oci-1-1" || sbomDeployMode == "legacy") ? sbomDeployMode : "none"
}

// Scans the already-pushed image straight from the registry (no second build needed).
def generateSbom(String imageRef, String sbomFile) {
  // Kaniko's registry credentials live only in its own container; copy them onto the
  // shared workspace so the Syft container below can reuse them to pull the image.
  def dockerConfigDir = "${env.WORKSPACE}/.docker-config-for-sbom"
  sh "mkdir -p ${dockerConfigDir} && cp /kaniko/.docker/config.json ${dockerConfigDir}/config.json"

  container(Constants.SYFT_CONTAINER) {
    sh """
      DOCKER_CONFIG=${dockerConfigDir} syft ${imageRef} \
          --scope all-layers \
          --output cyclonedx-json=${sbomFile}
      test -s ${sbomFile}
      grep -Eq '"bomFormat"[[:space:]]*:[[:space:]]*"CycloneDX"' ${sbomFile}
    """
  }
}

// Attaches the already-generated SBOM to the image. "oci-1-1" uses the real referrers API
// (confirmed working on Harbor); "legacy" uses cosign's tag-based fallback, which works
// on any registry, for destinations whose OCI 1.1 support isn't confirmed yet.
def deploySbomToRegistry(String imageRef, String sbomFile, String sbomDeployMode) {
  def cosignBinary = downloadCosign()

  def modeEnv = ""
  def modeArgs = ""
  if (sbomDeployMode == "oci-1-1") {
    modeEnv = "COSIGN_EXPERIMENTAL=1 "
    modeArgs = "--registry-referrers-mode oci-1-1"
  }

  sh """
    DOCKER_CONFIG=/kaniko/.docker ${modeEnv}${cosignBinary} attach sbom \
        --sbom ${sbomFile} \
        --type cyclonedx \
        ${modeArgs} \
        "${imageRef}"
  """
}

// cosign/curl are not available on this Jenkins agent, so fetch the cosign binary
// once via Maven's wagon plugin instead (mvn is guaranteed in the Maven container).
def downloadCosign() {
  def cosignVersion = "v2.4.1"
  def cosignBinary = "${env.WORKSPACE}/target/tools/cosign-linux-amd64"
  if (!fileExists(cosignBinary)) {
    container(Constants.MAVEN_JDK_17_CONTAINER) {
      sh """
        mvn -q org.codehaus.mojo:wagon-maven-plugin:3.0.0:download-single \
            -Dwagon.url=https://github.com/sigstore/cosign/releases/download/${cosignVersion} \
            -Dwagon.fromFile=cosign-linux-amd64 \
            -Dwagon.toDir=target/tools
        chmod +x ${cosignBinary}
      """
    }
  }
  return cosignBinary
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
