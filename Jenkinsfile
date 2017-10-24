podTemplate(label: 'sanbase-builder', containers: [
  containerTemplate(name: 'docker', image: 'docker', ttyEnabled: true, command: 'cat')
]) {
  node('sanbase-builder') {
    stage('Run Tests') {
      container('docker') {
        stage 'Checkout'
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
          docker.withServer('tcp://docker-host-docker-host:2375') {
            stage 'Run tests'
            docker.image("postgres:9.6-alpine").withRun { dbImage ->
              docker.build("sanbase-test:${env.BRANCH_NAME}", '-f Dockerfile-test .').inside("--link ${dbImage.id}:db") {
                "sh mix test"
              }
            }

#            if (env.BRANCH_NAME == "master") {
              stage 'Push to registry'
              docker.withRegistry("${env.aws_account_id}.dkr.ecr.eu-central-1.amazonaws.com", "ecr:eu-central-1:ecr-credentials") {
                def image = docker.build("sanbase")

                image.push(env.BRANCH_NAME)
                image.push(env.GIT_COMMIT)
              }
#            }
          }
        }
      }
    }
  }
}
