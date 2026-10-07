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
    choice(
      name: 'DISTRO',
      choices: ['ALL', 'tomcat', 'wildfly', 'run', 'run4'],
      description: 'Distribution to build and deploy (ALL builds and deploys every distribution, one by one)'
    )
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
          def snapshot = sh(
            script: 'grep SNAPSHOT= Dockerfile | head -n1 | cut -d = -f 2',
            returnStdout: true
          ).trim()
          if (snapshot == 'true') {
            cibsevenVersion += '-SNAPSHOT'
          }
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
            getDistrosToBuild().each { distro ->
              pushImage("harbor.cib.de/dev", "linux/amd64", cibsevenVersion, distro, "oci-1-1")
            }
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
            getDistrosToBuild().each { distro ->
              pushImage("docker.io/cibseven", "linux/amd64", cibsevenVersion, distro, "none")
            }
          }
        }
      }
    }

  }
}

// Returns the list of distros to build: all of them if DISTRO == 'ALL', otherwise just the selected one.
def getDistrosToBuild() {
  return params.DISTRO == 'ALL' ? ['tomcat', 'wildfly', 'run', 'run4'] : [params.DISTRO]
}

def pushImage(String destination, String platform, String cibsevenVersion, String distro, String sbomDeployMode) {
  withMaven(options: []) {
    def prefix = ""
    if (platform == "linux/arm64") {
      prefix = "arm64-"
    }
    if (distro && distro != '') {
      prefix = prefix + "${distro}-"
    }

    def isDefault = distro == 'tomcat'
    def deployLatest = !cibsevenVersion.endsWith('-SNAPSHOT')
    def distroArg = "--build-arg DISTRO=\"${distro}\""
    def isSnapshot = !deployLatest
    def baseVersion = cibsevenVersion.replace('-SNAPSHOT', '')
    def versionArg = "--build-arg VERSION=\"${baseVersion}\""
    def snapshotArg = "--build-arg SNAPSHOT=${isSnapshot}"
    def imageTag = "${prefix}${cibsevenVersion}"
    def sbomFile = "cibseven-${imageTag}.cdx.json"
    def primaryImageRef = "${destination}/cibseven:${imageTag}"
    sbomDeployMode = (sbomDeployMode == "oci-1-1") ? sbomDeployMode : "none"

    def destinations = "--destination=\"${destination}/cibseven:${prefix}${cibsevenVersion}\""
    if (deployLatest) {
      destinations += " --destination=\"${destination}/cibseven:${prefix}latest\""
      if (isDefault) {
        destinations += " --destination=\"${destination}/cibseven:${cibsevenVersion}\""
        destinations += " --destination=\"${destination}/cibseven:latest\""
      }
    }

    // Clean Kaniko workspace BEFORE build to prevent layer accumulation across the
    // multiple sequential builds that can now happen in one pod (DISTRO=ALL, and/or
    // both destinations enabled).
    // TEMPORARY DEBUG: show what's actually in these paths before/after cleanup,
    // to confirm whether the rm -rf below is actually taking effect.
    sh """
      echo "--- BEFORE cleanup (distro=${distro}) ---"
      du -sh /workspace /kaniko/0 /kaniko/1 2>/dev/null || true
      rm -rf /workspace/* /kaniko/.docker/* /kaniko/0 /kaniko/1 2>/dev/null || true
      echo "--- AFTER cleanup (distro=${distro}) ---"
      du -sh /workspace /kaniko/0 /kaniko/1 2>/dev/null || true
    """

    sh """
      /kaniko/executor --dockerfile `pwd`/Dockerfile \
          --context `pwd` \
          --custom-platform=${platform} \
          ${destinations} \
          ${distroArg} \
          ${versionArg} \
          ${snapshotArg}
    """

    if (sbomDeployMode != "none") {
      generateSbom(primaryImageRef, sbomFile)
      deploySbomToRegistry(primaryImageRef, sbomFile)
    }
  }
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

  // Held a copy of the registry credentials - remove it once it's no longer needed.
  sh "rm -rf ${dockerConfigDir}"
}

// Attaches the already-generated SBOM to the image via the real OCI 1.1 referrers API
// (confirmed working on Harbor).
def deploySbomToRegistry(String imageRef, String sbomFile) {
  def cosignBinary = downloadCosign()

  sh """
    DOCKER_CONFIG=/kaniko/.docker COSIGN_EXPERIMENTAL=1 ${cosignBinary} attach sbom \
        --sbom ${sbomFile} \
        --type cyclonedx \
        --registry-referrers-mode oci-1-1 \
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
