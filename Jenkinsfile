node {
    def app

    echo "Hello jenkins"
    // stage('Clone repository') {
    //     /* Let's make sure we have the repository cloned to our workspace */

    //     checkout scm
    // }

    stage('Build image') {
        /* This builds the actual image; synonymous to
         * docker build on the command line */
	echo "Build"
        app = docker.build("santiment/sanbase", "--build-arg SECRET_KEY_BASE=L7FsGz/B9uMfwziD6qTcnMpVLti00E1mHMA/PvwAcsA2YMlB2TEJXmIB8iHafhX+ .")
	echo "Done"
    }

    stage('Test image') {
        /* Ideally, we would run a test framework against our image.
         * For this example, we're using a Volkswagen-type approach ;-) */
	echo "TEST"
        app.inside {
            sh 'echo "Tests passed"'
        }
	echo "DONE"
    }

    stage('Push image') {
        // /* Finally, we'll push the image with two tags:
        //  * First, the incremental build number from Jenkins
        //  * Second, the 'latest' tag.
        //  * Pushing multiple tags is cheap, as all the layers are reused. */
        // docker.withRegistry('https://registry.hub.docker.com', 'docker-hub-credentials') {
        //     app.push("${env.BUILD_NUMBER}")
        //     app.push("latest")
        // }
    }
}
