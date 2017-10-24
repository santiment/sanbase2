podTemplate(label: 'sanbase-builder', containers: [
  containerTemplate(name: 'docker', image: 'docker', ttyEnabled: true, command: 'cat', envVars: [
    envVar(key: 'DOCKER_HOST', value: 'tcp://docker-host-docker-host:2375')
  ]),
  containerTemplate(
    name: 'db',
    image: 'postgres:9.6-alpine',
    ttyEnabled: true,
    ports: [portMapping(name: 'postgres', containerPort: 5432, hostPort: 5432)])
]) {
  node('sanbase-builder') {
    stage('Run Tests') {
      container('docker') {
        checkout scm

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
            sh "docker build -t ${awsRegistry}/sanbase:${env.BRANCH_NAME} -t ${awsRegistry}/sanbase:${env.GIT_COMMIT} ."
            sh "docker push ${awsRegistry}/sanbase:${env.BRANCH_NAME}"
            sh "docker push ${awsRegistry}/sanbase:${env.GIT_COMMIT}"
          }

          sh "docker build -t sanbase-test:${env.BRANCH_NAME} -f Dockerfile-test ."
          sh "docker run --rm --env DATABASE_URL=postgres://postgres:password@db:5432/postgres -t sanbase-test:${env.BRANCH_NAME}"
        }
      }
    }
  }
}
