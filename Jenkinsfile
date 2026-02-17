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

def numPartitions = 4

slaveTemplates.dockerTemplate { label ->
  node(label) {
    stage('Build Test Image') {
      container('docker') {
        def scmVars = checkout scm
        def gitHead = scmVars.GIT_COMMIT.substring(0, 7)
        def sanitizedBranchName = env.BRANCH_NAME.replaceAll('/', '-')
        def imageTag = "sanbase-test:${scmVars.GIT_COMMIT}-${env.BUILD_ID}-${sanitizedBranchName}-${env.CHANGE_ID}"

        sh "docker build \
          -t ${imageTag} \
          -f Dockerfile-test . \
          --progress plain"

        // Store variables for later stages
        env.TEST_IMAGE_TAG = imageTag
        env.GIT_HEAD = gitHead
        env.GIT_COMMIT_FULL = scmVars.GIT_COMMIT
      }
    }

    stage('Run Tests') {
      container('docker') {
        catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') {
          def imageTag = env.TEST_IMAGE_TAG
          def buildSuffix = "${env.GIT_COMMIT_FULL}-${env.BUILD_ID}"
          def failuresDir = "${pwd()}/test_failures_${buildSuffix}"

          sh "mkdir -p ${failuresDir}"

          // Start postgres containers for each partition
          for (int i = 1; i <= numPartitions; i++) {
            sh "docker run \
              --rm --name test-postgres-${buildSuffix}-p${i} \
              -e POSTGRES_PASSWORD=password \
              -d pgvector/pgvector:pg15"
          }

          try {
            def partitions = [:]

            for (int i = 1; i <= numPartitions; i++) {
              def partition = i
              partitions["Partition ${partition}"] = {
                sh "docker run --rm \
                  --link test-postgres-${buildSuffix}-p${partition}:test-db \
                  --env DATABASE_URL=postgres://postgres:password@test-db:5432/postgres \
                  --env MIX_TEST_PARTITION=${partition} \
                  -v ${failuresDir}:/app/_build/test/failures \
                  -t ${imageTag} \
                  mix test --partitions ${numPartitions} \
                    --formatter Sanbase.FailedTestFormatter \
                    --formatter ExUnit.CLIFormatter \
                    --slowest 20"
              }
            }

            parallel partitions
          } finally {
            for (int i = 1; i <= numPartitions; i++) {
              sh "docker kill test-postgres-${buildSuffix}-p${i} || true"
            }
          }
        }
      }
    }

    stage('Summarize Test Failures') {
      def buildSuffix = "${env.GIT_COMMIT_FULL}-${env.BUILD_ID}"
      def failuresDir = "${pwd()}/test_failures_${buildSuffix}"

      sh """
        echo ''
        echo '========================================'
        echo '  Combined results from all partitions'
        echo '========================================'
        if ls ${failuresDir}/partition_*.txt 1>/dev/null 2>&1; then
          echo 'Failing tests across all partitions:'
          cat ${failuresDir}/partition_*.txt | cut -f2 | sort
          echo ''
          echo 'Re-run with:'
          echo "  mix test \$(cat ${failuresDir}/partition_*.txt | cut -f2 | tr '\\n' ' ')"
        else
          echo 'All partitions passed!'
        fi

        rm -rf ${failuresDir}
      """
    }

    if (env.BRANCH_NAME == 'master') {
      stage('Build & Push') {
        container('docker') {
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
                -t ${awsRegistry}/sanbase:${env.GIT_COMMIT_FULL} \
                --build-arg SECRET_KEY_BASE=${env.SECRET_KEY_BASE} \
                --build-arg PARITY_URL=${env.PARITY_URL} \
                --build-arg GIT_HEAD=${env.GIT_HEAD} \
                --build-arg GIT_COMMIT=${env.GIT_COMMIT_FULL} . \
                --progress plain"

              sh "docker push ${awsRegistry}/sanbase:${env.BRANCH_NAME}"
              sh "docker push ${awsRegistry}/sanbase:${env.GIT_COMMIT_FULL}"
            }
          }
        }
      }
    }
  }
}
