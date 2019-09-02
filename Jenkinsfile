podTemplate(label: 'sanbase-builder', containers: [
  containerTemplate(
    name: 'docker-compose',
    image: 'docker/compose:1.24.1',
    ttyEnabled: true,
    command: 'cat',
    envVars: [
      envVar(key: 'DOCKER_BUILDKIT', value: '1'),
      envVar(key: 'DOCKER_HOST', value: 'tcp://docker-host-docker-host:2375')

    ])
]) {
  node('sanbase-builder') {
    container('docker-compose') {

    def scmVars = checkout scm

    stage('docker-compose') {
        try {
          sh "docker-compose -f docker-compose-test.yaml build"
          sh "docker-compose -f docker-compose-test.yaml run test"
        } finally {
          sh "docker-compose -f docker-compose-test.yaml down -v"
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

            def gitHead = scmVars.GIT_COMMIT.substring(0,7)
            def awsRegistry = "${env.aws_account_id}.dkr.ecr.eu-central-1.amazonaws.com"

            docker.withRegistry("https://${awsRegistry}", "ecr:eu-central-1:ecr-credentials") {
              sh "docker build \
                -t ${awsRegistry}/sanbase:${env.BRANCH_NAME} \
                -t ${awsRegistry}/sanbase:${scmVars.GIT_COMMIT} \
                --build-arg SECRET_KEY_BASE=${env.SECRET_KEY_BASE} \
                --build-arg GIT_HEAD=${gitHead} . \
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
