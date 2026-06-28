#!/usr/bin/env bash
# ==========================================================================
# 01 - Instala las herramientas dentro de WSL2 (Ubuntu).
# Ejecuta:  bash scripts/01-setup-wsl-tools.sh
# ==========================================================================
set -e

echo ">> Actualizando paquetes base..."
sudo apt-get update -y
sudo apt-get install -y curl unzip git apt-transport-https ca-certificates gnupg

# ---- AWS CLI v2 ----
if ! command -v aws >/dev/null 2>&1; then
  echo ">> Instalando AWS CLI v2..."
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
  unzip -q awscliv2.zip
  sudo ./aws/install
  rm -rf aws awscliv2.zip
fi
aws --version

# ---- kubectl ----
if ! command -v kubectl >/dev/null 2>&1; then
  echo ">> Instalando kubectl..."
  curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
fi
kubectl version --client

# ---- eksctl ----
if ! command -v eksctl >/dev/null 2>&1; then
  echo ">> Instalando eksctl..."
  ARCH=amd64
  PLATFORM=$(uname -s)_$ARCH
  curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_${PLATFORM}.tar.gz"
  tar -xzf eksctl_${PLATFORM}.tar.gz -C /tmp && rm eksctl_${PLATFORM}.tar.gz
  sudo mv /tmp/eksctl /usr/local/bin
fi
eksctl version

echo ""
echo ">> Docker: se usa Docker Desktop con integracion WSL2 activada."
echo "   Verifica con:  docker version"
echo ""
echo "Listo. Herramientas instaladas."
