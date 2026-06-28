#!/usr/bin/env bash
# ==========================================================================
# 04 - Despliega TODO en el cluster: namespace, secret, mysql, backends,
#      frontend y HPA. Reemplaza <ACCOUNT_ID> por tu cuenta automaticamente.
# Pre-requisito: el cluster EKS ya existe y kubectl apunta a el.
# ==========================================================================
set -e
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo ">> Renderizando manifiestos con ACCOUNT_ID=$ACCOUNT_ID..."
mkdir -p infra/k8s/_rendered
for f in infra/k8s/*.yaml; do
  base=$(basename "$f")
  sed "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" "$f" > "infra/k8s/_rendered/$base"
done

echo ">> Instalando metrics-server (necesario para HPA)..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo ">> Aplicando manifiestos..."
kubectl apply -f infra/k8s/_rendered/00-namespace.yaml
kubectl apply -f infra/k8s/_rendered/01-secrets.yaml
kubectl apply -f infra/k8s/_rendered/02-mysql.yaml
echo "   Esperando a MySQL..."
kubectl rollout status deployment/mysql -n innovatech --timeout=180s || true
kubectl apply -f infra/k8s/_rendered/03-ventas.yaml
kubectl apply -f infra/k8s/_rendered/04-despachos.yaml
kubectl apply -f infra/k8s/_rendered/05-frontend.yaml
kubectl apply -f infra/k8s/_rendered/06-hpa.yaml

echo ""
echo ">> Estado:"
kubectl get pods,svc,hpa -n innovatech
echo ""
echo ">> URL publica del frontend (puede tardar 2-3 min en aparecer el DNS):"
kubectl get svc frontend-svc -n innovatech \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
