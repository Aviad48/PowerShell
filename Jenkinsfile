pipeline {
    agent any

    stages {

        stage('Deploy Local Folder') {
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

                    sh """
                        mkdir -p ${target}

                        rsync -av --delete \
                        --exclude='.git' \
                        ./ ${target}/
                    """
                }
            }
        }

        stage('Approve Promotion') {

            when {
                anyOf {
                    branch 'test'
                    branch 'dev'
                }
            }

            steps {

                input message: "Approve promotion?"
            }
        }

    }
}
