#!/usr/bin/env bash
# ==========================================================================
# 02 - Crea los 3 repositorios en Amazon ECR.
# Requiere credenciales de Learner Lab ya configuradas (aws configure / ~/.aws).
# ==========================================================================
set -e
REGION="us-east-1"

for repo in innovatech-ventas innovatech-despachos innovatech-frontend; do
  echo ">> Creando repo ECR: $repo"
  aws ecr create-repository \
    --repository-name "$repo" \
    --region "$REGION" \
    --image-scanning-configuration scanOnPush=true \
    >/dev/null 2>&1 || echo "   (ya existia, ok)"
done

echo ""
echo ">> Repos ECR disponibles:"
aws ecr describe-repositories --region "$REGION" \
  --query "repositories[].repositoryUri" --output table
