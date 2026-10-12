// Multi-stage pipeline: checks -> build/push -> canary deploy -> Istio 5xx guard -> human approval -> progressive promote.
// Use as a Multibranch Pipeline (so `branch 'main'` works). Agent label: docker.
pipeline {
  agent { label 'docker' }
  parameters {
    string(name: 'TAG', defaultValue: 'v2', description: 'Candidate image tag (canary)')
    string(name: 'REGISTRY_REPO', defaultValue: 'kaj1/fintrack-app', description: 'Registry repo')
  }
  options {
    timeout(time: 25, unit: 'MINUTES')            // never hang forever (Phase 2.3)
    timestamps()
    disableConcurrentBuilds()                      // one deploy at a time
    buildDiscarder(logRotator(numToKeepStr: '15')) // stop disk filling up
  }
  environment {
    NS = 'fintrack'
    CANDIDATE = "${params.REGISTRY_REPO}:${params.TAG}"
  }
  stages {
    stage('Checks') {
      parallel {
        stage('Secret scan')       { steps { sh './scripts/secret-scan.sh --all' } }
        stage('Validate manifests'){ steps { sh 'python3 scripts/validate-istio.py' } }
      }
    }
    stage('Build & push') {
      options { timeout(time: 10, unit: 'MINUTES') }
      steps {
        sh 'docker build -t "$CANDIDATE" app'
        withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh 'echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin && docker push "$CANDIDATE"'
        }
      }
    }
    stage('Deploy canary') {
      when { branch 'main' }
      steps {
        sh '''
          ./scripts/mark-release.sh deploying "$CANDIDATE"          # state first: a crashed agent leaves a trail
          kubectl -n $NS set image deploy/account-service-v2 app="$CANDIDATE"
          kubectl -n $NS rollout status deploy/account-service-v2 --timeout=180s
          kubectl apply -f istio/30-routing.yaml                     # 90/10
        '''
      }
    }
    stage('Canary guard (Istio 5xx)') {
      when { branch 'main' }
      steps { sh './scripts/canary-guard.sh 120 5' }                 // exit 1 => post{failure} => rollback
    }
    stage('Approve promotion') {
      when { branch 'main' }
      steps {
        timeout(time: 10, unit: 'MINUTES') {
          input message: 'Canary healthy. Promote?', submitter: 'admin,release-managers'   // only these users can ship main
        }
      }
    }
    stage('Promote') {
      when { branch 'main' }
      steps { sh './scripts/promote.sh "$CANDIDATE"' }
    }
  }
  post {
    failure { sh './scripts/rollback.sh --if-deploying || true'; script { notify('FAILED') } }     // rolls back to last_good_image (v1), not a guessed tag
    aborted { sh './scripts/rollback.sh --if-deploying || true'; script { notify('ABORTED/TIMED OUT') } }
    success { script { notify('SUCCESS') } }
    always  { sh 'docker logout || true; docker image prune -f --filter until=24h || true' }
  }
}

def notify(String status) {
  def msg = "FinTrack pipeline ${status}: ${env.JOB_NAME} #${env.BUILD_NUMBER} ${env.BUILD_URL}"
  echo msg
  withCredentials([string(credentialsId: 'slack-webhook', variable: 'HOOK')]) {
    sh "curl -s -m 10 -X POST -H 'Content-Type: application/json' -d '{\"text\":\"${msg}\"}' \"\$HOOK\" || true"
  }
}
