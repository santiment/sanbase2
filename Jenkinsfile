@Library('podTemplateLib')
import net.santiment.utils.podTemplates

properties([
  buildDiscarder(
    logRotator(artifactDaysToKeepStr: '30',
    artifactNumToKeepStr: '',
    daysToKeepStr: '30',
    numToKeepStr: ''))
  ])

slaveTemplates = new podTemplates()

slaveTemplates.dockerTemplate { label ->
  node(label) {
    stage('Run Tests') {
      container('docker') {
        def scmVars = checkout scm
        def gitHead = scmVars.GIT_COMMIT.substring(0, 7)

        sh "docker build \
          -t sanbase-test:${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.BRANCH_NAME}-${env.CHANGE_ID} \
          -f Dockerfile-test . \
          --progress plain"

        sh "docker run \
            --rm --name test-postgres-${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.BRANCH_NAME}-${env.CHANGE_ID} \
            -e POSTGRES_PASSWORD=password \
            -d postgres:12.7-alpine"

        try {
          sh "docker run --rm \
            --link test-postgres-${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.BRANCH_NAME}-${env.CHANGE_ID}:test-db \
            --env DATABASE_URL=postgres://postgres:password@test-db:5432/postgres \
            -t sanbase-test:${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.BRANCH_NAME}-${env.CHANGE_ID}"
        } finally {
          sh "docker kill test-postgres-${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.BRANCH_NAME}-${env.CHANGE_ID}"
        }

        if (env.BRANCH_NAME == 'master') {
          withCredentials([
            string(
              credentialsId: 'SECRET_KEY_BASE',
              variable: 'SECRET_KEY_BASE'
            ),
            string(
              credentialsId: 'PARITY_URL',
              variable: 'PARITY_URL'
            ),
            string(
              credentialsId: 'aws_account_id',
              variable: 'aws_account_id'
            )
          ]) {
            def awsRegistry = "${env.aws_account_id}.dkr.ecr.eu-central-1.amazonaws.com"
            docker.withRegistry("https://${awsRegistry}", 'ecr:eu-central-1:ecr-credentials') {
              sh "docker build \
                -t ${awsRegistry}/sanbase:${env.BRANCH_NAME} \
                -t ${awsRegistry}/sanbase:${scmVars.GIT_COMMIT} \
                --build-arg SECRET_KEY_BASE=${env.SECRET_KEY_BASE} \
                --build-arg PARITY_URL=${env.PARITY_URL} \
                --build-arg GIT_HEAD=${gitHead} \
                --build-arg GIT_COMMIT=${scmVars.GIT_COMMIT} . \
                --progress plain"

              sh "docker push ${awsRegistry}/sanbase:${env.BRANCH_NAME}"
              sh "docker push ${awsRegistry}/sanbase:${scmVars.GIT_COMMIT}"
            }
          }
        }
      }
    }
  }
}
