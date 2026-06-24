pipeline {
    agent any

    stages {

        stage('Deploy') {

            steps {

                script {

                    def target = ""

                    if (env.BRANCH_NAME == "test") {
                        target = "/home/ubuntu/docker_volume/test"
                    }

                    if (env.BRANCH_NAME == "dev") {
                        target = "/home/ubuntu/docker_volume/dev"
                    }

                    if (env.BRANCH_NAME == "main") {
                        target = "/home/ubuntu/docker_volume/main"
                    }

                    echo "Deploying ${env.BRANCH_NAME} to ${target}"

                    sh """
                    mkdir -p ${target}

                    rsync -av --delete \
                      --exclude='.git' \
                      ./ ${target}/
                    """
                }
            }
        }
    }
}
