#!/usr/bin/env bash
# ==========================================================================
# 03 - Build + push de las 3 imagenes a ECR (manual, desde tu WSL2).
# Sirve para la PRIMERA carga (antes de tener el pipeline) o para depurar.
# ==========================================================================
set -e
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
TAG="${1:-latest}"   # uso: bash 03-build-push.sh v1   (default: latest)

echo ">> Login a ECR ($REGISTRY)..."
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo ">> Build + push VENTAS..."
docker build -t "$REGISTRY/innovatech-ventas:$TAG" \
  ./back-ventas-springboot/api-rest-ventas
docker push "$REGISTRY/innovatech-ventas:$TAG"

echo ">> Build + push DESPACHOS..."
docker build -t "$REGISTRY/innovatech-despachos:$TAG" \
  ./back-bespachos-springboot/api-rest-despacho
docker push "$REGISTRY/innovatech-despachos:$TAG"

echo ">> Build + push FRONTEND..."
docker build -t "$REGISTRY/innovatech-frontend:$TAG" \
  ./front-despacho
docker push "$REGISTRY/innovatech-frontend:$TAG"

echo ""
echo "Listo. Imagenes en ECR con tag: $TAG"
