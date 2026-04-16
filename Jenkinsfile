pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: kaniko
    image: gcr.io/kaniko-project/executor:debug
    command: ["/busybox/sleep"]
    args: ["infinity"]
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "2"
        memory: "4Gi"
"""
        }
    }
    stages {
        stage('Stress Test - Kaniko Build') {
            steps {
                script {
                    // Parallel execution of 10 builds
                    def parallelBuilds = [:]
                    (1..10).each { i ->
                        parallelBuilds["build-${i}"] = {
                            container('kaniko') {
                                sh "/kaniko/executor --context dir://\$(pwd) --dockerfile Dockerfile --no-push"
                            }
                        }
                    }
                    parallel parallelBuilds
                }
            }
        }
    }
}
