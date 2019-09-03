@Library('podTemplateLib')
import net.santiment.utils.podTemplates

properties([buildDiscarder(logRotator(artifactDaysToKeepStr: '30', artifactNumToKeepStr: '', daysToKeepStr: '30', numToKeepStr: ''))])
slaveTemplates = new podTemplates()

slaveTemplates.dockerComposeTemplate { label ->
  node(label) {
    container('docker-compose') {

      def scmVars = checkout scm

      stage('Run Tests') {
        try {
          sh "docker-compose -f docker-compose-test.yaml build"
          sh "docker-compose -f docker-compose-test.yaml run test"
        } finally {
          sh "docker-compose -f docker-compose-test.yaml down -v"
        }
      }

      stage('Build & Push if Master') {
        if (env.BRANCH_NAME == "master") {
          withCredentials([
            string(
              credentialsId: 'aws_account_id',
              variable: 'aws_account_id'
            )
          ]) {
            def gitHead = scmVars.GIT_COMMIT.substring(0,7)
            def awsRegistry = "${env.aws_account_id}.dkr.ecr.eu-central-1.amazonaws.com"

            docker.withRegistry("https://${awsRegistry}", "ecr:eu-central-1:ecr-credentials") {
              sh "docker build \
                -t ${awsRegistry}/sanbase:${env.BRANCH_NAME} \
                -t ${awsRegistry}/sanbase:${scmVars.GIT_COMMIT} \
                --build-arg GIT_HEAD=${gitHead} . \
                --progress plain"

            }

            sh "docker push ${awsRegistry}/sanbase:${env.BRANCH_NAME}"
            sh "docker push ${awsRegistry}/sanbase:${scmVars.GIT_COMMIT}"
          }
        }
      }
    }
  }
}