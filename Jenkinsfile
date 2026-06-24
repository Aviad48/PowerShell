stage('Promote Dev To Main') {

    when {
        branch 'dev'
    }

    steps {

        sh '''
        git config user.email "jenkins@local"
        git config user.name "Jenkins"

        git checkout main
        git merge dev
        git push origin main
        '''
    }
}
