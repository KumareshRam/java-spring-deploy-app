pipeline {
  agent { label 'aws-deploy' }
  options { skipDefaultCheckout(true); timestamps(); disableConcurrentBuilds(); timeout(time: 100, unit: 'MINUTES') }
  parameters {
    string(name: 'AWS_REGION', defaultValue: 'ap-south-1')
    string(name: 'BACKEND_PROJECT', defaultValue: 'spring-backend-build')
    string(name: 'IMAGE_PROJECT', defaultValue: 'spring-image-build')
    string(name: 'ECR_REPOSITORY', defaultValue: 'spring-demo')
    string(name: 'EKS_CLUSTER', defaultValue: 'REPLACE_WITH_CLUSTER')
  }
  environment { AWS_PAGER = ''; KUBECONFIG = "${WORKSPACE}/.kubeconfig" }
  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.SOURCE_COMMIT = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
          env.RELEASE_ID = "${env.SOURCE_COMMIT.take(12)}-${env.BUILD_NUMBER}"
        }
      }
    }
    stage('CodeBuild: backend, security, ZIP, Artifactory') {
      steps { sh 'python3 ci/run_build.py "$BACKEND_PROJECT" "$SOURCE_COMMIT" "$RELEASE_ID"' }
    }
    stage('CodeBuild: download ZIP, Docker, security, ECR') {
      steps { sh 'python3 ci/run_build.py "$IMAGE_PROJECT" "$SOURCE_COMMIT" "$RELEASE_ID"' }
    }
    stage('Deploy to Kubernetes and verify') {
      steps { sh 'bash ci/deploy.sh' }
    }
  }
  post { always { sh 'rm -f "$KUBECONFIG"' } }
}
