#!/usr/bin/env bash
set -euo pipefail
: "${EKS_CLUSTER:?}" "${AWS_REGION:?}" "${ECR_REPOSITORY:?}" "${RELEASE_ID:?}"
account=$(aws sts get-caller-identity --query Account --output text)
digest=$(aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids "imageTag=$RELEASE_ID" --query 'imageDetails[0].imageDigest' --output text)
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo 'No valid ECR digest'; exit 1; }
export DEPLOY_IMAGE="$account.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY@$digest"
# KUBECONFIG is workspace-local; the Jenkins IAM role needs namespace access.
aws eks update-kubeconfig --name "$EKS_CLUSTER" --region "$AWS_REGION"
kubectl auth can-i patch deployments -n spring-demo | grep -qx yes
python3 - <<'RENDER'
import os
from pathlib import Path
p=Path('k8s/deployment.yaml').read_text().replace('__IMAGE__',os.environ['DEPLOY_IMAGE'])
Path('deployment-rendered.yaml').write_text(p)
RENDER
kubectl apply -f deployment-rendered.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/spring-demo -n spring-demo --timeout=300s
# Wait for public address, then verify an actual HTTP response through the NLB.
for attempt in $(seq 1 60); do
  endpoint=$(kubectl get service spring-demo -n spring-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  if [[ -n "$endpoint" ]] && curl --fail --silent --show-error --connect-timeout 5 --max-time 10 "http://$endpoint/" -o response.txt; then
    grep -q 'Greetings from Spring Boot!' response.txt
    echo "Application URL: http://$endpoint/"; cat response.txt; exit 0
  fi
  sleep 10
done
echo 'External HTTP verification failed. Check Service events, NLB targets and subnet tags.'
exit 1
