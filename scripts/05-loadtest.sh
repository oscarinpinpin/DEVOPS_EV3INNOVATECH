#!/usr/bin/env bash
# ==========================================================================
# 05 - Genera carga sobre el backend de ventas para DISPARAR el autoscaling.
# Lanza un pod temporal que machaca el endpoint en un loop.
# En OTRA terminal observa el escalado con:
#     kubectl get hpa -n innovatech -w
#     kubectl get pods -n innovatech -w
# Corta este script con Ctrl+C cuando ya hayas capturado la evidencia.
# ==========================================================================
set -e
echo ">> Lanzando generador de carga contra ventas-svc:8080 ..."
echo ">> (Ctrl+C para detener)"
kubectl run carga --rm -it --restart=Never -n innovatech --image=busybox:1.36 -- \
  /bin/sh -c "while true; do wget -q -O- http://ventas-svc:8080/api/v1/ventas >/dev/null; done"
