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
          docker.withRegistry("${env.aws_account_id}.dkr.ecr.eu-central-1.amazonaws.com", "ecr:eu-central-1:ecr-credentials") {
            def image = docker.build("sanbase", '.')

            image.push(env.BRANCH_NAME)
            image.push(env.GIT_COMMIT)
          }
          docker.build("sanbase-test:${env.BRANCH_NAME}", '-f Dockerfile-test .').run()
        }
      }
    }
  }
}
