stage('Promote Test To Dev') {

    when {
        branch 'test'
    }

    steps {

        sh '''
        git config user.email "jenkins@local"
        git config user.name "Jenkins"

        git checkout dev
        git merge test
        git push origin dev
        '''
    }
}
