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

        sh "docker build -t sanbase-test:${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.CHANGE_ID} -f Dockerfile-test ."
        sh "docker run --rm --name test-postgres-${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.CHANGE_ID} -d timescale/timescaledb:0.10.1-pg10"
        sh "docker run --rm --name test-influxdb-${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.CHANGE_ID} -d influxdb:1.4-alpine"
        try {
          sh "docker run --rm \
            --link test-postgres-${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.CHANGE_ID}:test-db \
            --link test-influxdb-${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.CHANGE_ID}:test-influxdb \
            --env DATABASE_URL=postgres://postgres:password@test-db:5432/postgres \
            --env TIMESCALE_DATABASE_URL=postgres://postgres:password@test-db:5432/postgres \
            --env CLICKHOUSE_DATABASE_URL=postgres://postgres:password@test-db:5432/postgres \
            --env INFLUXDB_HOST=test-influxdb \
            --env ETHERBI_INFLUXDB_HOST=test-influxdb \
            -t sanbase-test:${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.CHANGE_ID}"
        } finally {
          sh "docker kill test-influxdb-${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.CHANGE_ID}"
          sh "docker kill test-postgres-${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${env.CHANGE_ID}"
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
