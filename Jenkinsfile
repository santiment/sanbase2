podTemplate(label: 'sanbase-builder', containers: [
  containerTemplate(name: 'docker', image: 'docker', ttyEnabled: true, command: 'cat', envVars: [
    envVar(key: 'DOCKER_HOST', value: 'tcp://docker-host-docker-host:2375')
  ])
]) {
  node('sanbase-builder') {
    stage('Run Tests') {
      container('docker') {
        def scmVars = checkout scm
        def gitHead = scmVars.GIT_COMMIT.substring(0,7)

        sh "docker build -t sanbase-test:${scmVars.GIT_COMMIT} -f Dockerfile-test ."
        sh "docker build -t sanbase-frontend-test:${scmVars.GIT_COMMIT} -f app/Dockerfile-test app"
        sh "docker run --rm --name test_postgres_${scmVars.GIT_COMMIT} -d postgres:9.6-alpine"
        sh "docker run --rm --name test_influxdb_${scmVars.GIT_COMMIT} -d influxdb:1.4-alpine"
        try {
          sh "docker run --rm \
            --link test_postgres_${scmVars.GIT_COMMIT}:test_db \
            --link test_influxdb_${scmVars.GIT_COMMIT}:test_influxdb \
            --env DATABASE_URL=postgres://postgres:password@test_db:5432/postgres \
            --env CLICKHOUSE_DATABASE_URL=postgres://postgres:password@test_db:5432/postgres \
            --env INFLUXDB_HOST=test_influxdb \
            --env ETHERBI_INFLUXDB_HOST=test_influxdb \
            -t sanbase-test:${scmVars.GIT_COMMIT}"
          sh "docker run --rm -t sanbase-frontend-test:${scmVars.GIT_COMMIT} yarn test --ci"
        } finally {
          sh "docker kill test_influxdb_${scmVars.GIT_COMMIT}"
          sh "docker kill test_postgres_${scmVars.GIT_COMMIT}"
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
              sh "docker build -t ${awsRegistry}/sanbase:${env.BRANCH_NAME} -t ${awsRegistry}/sanbase:${scmVars.GIT_COMMIT} --build-arg SECRET_KEY_BASE=${env.SECRET_KEY_BASE} --build-arg GIT_HEAD=${gitHead} ."
              sh "docker push ${awsRegistry}/sanbase:${env.BRANCH_NAME}"
              sh "docker push ${awsRegistry}/sanbase:${scmVars.GIT_COMMIT}"
            }
          }
        }
      }
    }
  }
}
