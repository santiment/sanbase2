podTemplate(label: 'sanbase-builder', containers: [
  containerTemplate(name: 'docker', image: 'docker', ttyEnabled: true, command: 'cat', envVars: [
    envVar(key: 'DOCKER_HOST', value: 'tcp://docker-host-docker-host:2375')
  ])
]) {
  node('sanbase-builder') {
    stage('Run Tests') {
      container('docker') {
        def scmVars = checkout scm

        sh "docker build -t sanbase-test:${env.BRANCH_NAME} -f Dockerfile-test ."
        sh "docker build -t sanbase-frontend-test:${env.BRANCH_NAME} -f
        app/Dockerfile-test app"
        sh "docker run --rm --name test_postgres_${env.BRANCH_NAME} -d postgres:9.6-alpine"
        sh "docker run --rm --name test_influxdb_${env.BRANCH_NAME} -d influxdb:1.3-alpine"
        try {
          sh "docker run --rm --link test_postgres_${env.BRANCH_NAME}:test_db --link test_influxdb_${env.BRANCH_NAME}:test_influxdb --env DATABASE_URL=postgres://postgres:password@test_db:5432/postgres --env INFLUXDB_HOST=test_influxdb -t sanbase-test:${env.BRANCH_NAME}"
          sh "docker run --rm -t sanbase-frontend-test:${env.BRANCH_NAME}"
        } finally {
          sh "docker kill test_influxdb_${env.BRANCH_NAME}"
          sh "docker kill test_postgres_${env.BRANCH_NAME}"
        }

        if (env.BRANCH_NAME == "master") {
          withCredentials([
            string(
              credentialsId: 'SECRET_KEY_BASE',
              variable: 'SECRET_KEY_BASE'
            ),
            string(
              credentialsId: 'aws_account_id',
              variable: 'aws_account_id'
            )
          ]) {

            def awsRegistry = "${env.aws_account_id}.dkr.ecr.eu-central-1.amazonaws.com"
            docker.withRegistry("https://${awsRegistry}", "ecr:eu-central-1:ecr-credentials") {
              sh "docker build -t ${awsRegistry}/sanbase:${env.BRANCH_NAME} -t ${awsRegistry}/sanbase:${scmVars.GIT_COMMIT} --build-arg SECRET_KEY_BASE=${env.SECRET_KEY_BASE} ."
              sh "docker push ${awsRegistry}/sanbase:${env.BRANCH_NAME}"
              sh "docker push ${awsRegistry}/sanbase:${scmVars.GIT_COMMIT}"
            }
          }
        }
      }
    }
  }
}
