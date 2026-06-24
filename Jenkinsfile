pipeline {
    agent any

    stages {

        stage('Deploy') {

            steps {

                script {

                    def target = ""

                    switch(env.BRANCH_NAME) {

                        case "test":
                            target = "/data/test"
                            break

                        case "dev":
                            target = "/data/dev"
                            break

                        case "main":
                            target = "/data/prod"
                            break

                        default:
                            error("Unknown branch: ${env.BRANCH_NAME}")
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
