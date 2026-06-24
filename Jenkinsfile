pipeline {
    agent any

    stages {

        stage('Build') {
            steps {
                echo "Building ${env.BRANCH_NAME}"
            }
        }

        stage('Deploy') {
            steps {
                script {

                    if (env.BRANCH_NAME == 'test') {

                        sh 'deploy-test.sh'

                    } else if (env.BRANCH_NAME == 'dev') {

                        sh 'deploy-dev.sh'

                    } else if (env.BRANCH_NAME == 'main') {

                        sh 'deploy-prod.sh'
                    }
                }
            }
        }
    }
}
