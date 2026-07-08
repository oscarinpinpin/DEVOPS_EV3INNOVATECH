# InnovaTech — CI/CD y Orquestación en Amazon EKS

**Evaluación Final Transversal (EFT) · ISY1101 — Introducción a Herramientas DevOps**

Despliegue productivo de la plataforma **InnovaTech** sobre un clúster **Amazon EKS**, con
entrega continua mediante **GitHub Actions** (build → test → push a **ECR** → deploy) y **escalado
automático horizontal (HPA)**. La solución orquesta una arquitectura de microservicios compuesta por
dos APIs REST en Spring Boot, un frontend React servido por nginx y una base de datos MySQL,
garantizando escalabilidad, tolerancia a fallos, balanceo de carga y despliegue automatizado.

## Integrantes
- **Oscar Báez**
- **Benjamín Araya**

**Repositorio:** https://github.com/oscarinpinpin/DEVOPS_EV3INNOVATECH

---

## Cumplimiento de la rúbrica (mapa rápido)

| Indicador de la rúbrica | Dónde se evidencia en el repo |
|---|---|
| **IE1** Gestión de versiones y arquitectura | Historial Git · `README.md` · diagrama (sección 2) |
| **IE2** Contenerización | Dockerfiles multietapa en cada componente · `.dockerignore` |
| **IE3** Pipeline CI/CD | `.github/workflows/deploy.yml` (build → push → deploy) |
| **IE4** Despliegue y orquestación en la nube | `infra/eks-cluster.yaml` · `infra/k8s/` · HPA |
| **IE5** Verificación y funcionalidad | Sección 9 (flujo end-to-end, self-healing, HTTP 200) |
| Registro de imágenes | `scripts/02-ecr-create.sh` · tag = SHA del commit |
| Secretos y mínimo privilegio | `infra/k8s/01-secrets.yaml` · GitHub Secrets · LabRole/IAM |
| Observabilidad | `kubectl logs` · `kubectl top` · logs de Actions · CloudWatch |

---

## Índice
1. [Contexto y objetivos](#1-contexto-y-objetivos)
2. [Arquitectura final](#2-arquitectura-final)
3. [Clúster EKS](#3-clúster-eks)
4. [Despliegue de servicios](#4-despliegue-de-servicios)
5. [Autoscaling (HPA)](#5-autoscaling-hpa)
6. [Pipeline CI/CD](#6-pipeline-cicd)
7. [Secretos y credenciales](#7-secretos-y-credenciales)
8. [Observabilidad](#8-observabilidad)
9. [Validación funcional y tolerancia a fallos](#9-validación-funcional-y-tolerancia-a-fallos)
10. [Problemas y soluciones](#10-problemas-y-soluciones)
11. [Estructura del repositorio](#11-estructura-del-repositorio)
12. [Cómo reproducir el despliegue](#12-cómo-reproducir-el-despliegue)

---

## 1. Contexto y objetivos

InnovaTech avanza hacia la automatización y orquestación productiva de su aplicación de despachos.
Objetivos de esta etapa:

- Ejecutar la aplicación de forma **escalable, tolerante a fallos y automatizable**.
- **Automatizar completamente** los despliegues desde GitHub con GitHub Actions.
- Garantizar **escalado, autorrecuperación, logs, balanceo y disponibilidad** ante cambios o fallos.
- Usar **EKS** (Kubernetes gestionado) como plataforma de orquestación en producción.

Flujo de negocio: **una venta genera un despacho, y el despacho se cierra.**

---

## 2. Arquitectura final

```
                          Internet
                             │
                ┌────────────▼─────────────┐   Service type LoadBalancer
                │     frontend (nginx)      │   → ELB público de AWS
                │  SPA React + reverse proxy│
                └───┬──────────────────┬────┘
        /api/v1/ventas          /api/v1/despachos     (DNS interno del clúster)
                   │                  │
            ┌──────▼─────┐     ┌──────▼───────┐
            │   ventas   │     │   despachos  │       Service ClusterIP
            │ Spring Boot│     │ Spring Boot  │       (no expuestos a Internet)
            │   :8080    │     │    :8081     │
            └──────┬─────┘     └──────┬───────┘
                   └────────┬─────────┘
                     ┌──────▼──────┐
                     │    mysql    │   Service ClusterIP (headless)
                     │ ventasdb /  │   (interno)
                     │ despachosdb │
                     └─────────────┘
```

**Decisiones de diseño:**

- **El frontend es el único componente expuesto** → reduce la superficie de ataque; backends y BD
  quedan solo accesibles dentro del clúster (`ClusterIP`).
- **nginx como reverse proxy** → sirve el SPA y redirige `/api/v1/ventas` → `ventas-svc` y
  `/api/v1/despachos` → `despachos-svc`. Elimina CORS (mismo origen) y evita recompilar el front al
  cambiar la URL del balanceador.
- **Comunicación Front → Back por DNS interno** (`ventas-svc`, `despachos-svc`) vía CoreDNS.
- **URLs relativas** en el front (`VITE_API_BASE` vacío en producción) → la misma imagen funciona sin
  importar el DNS del ELB.

| Componente | Tecnología | Puerto | Service | Acceso |
|---|---|---|---|---|
| Frontend | React + Vite + nginx | 80 | LoadBalancer | Público (ELB) |
| API Ventas | Spring Boot 3.4 / Java 17 | 8080 | ClusterIP | Interno |
| API Despachos | Spring Boot 3.4 / Java 17 | 8081 | ClusterIP | Interno |
| Base de datos | MySQL 8 | 3306 | ClusterIP (headless) | Interno |

> **URL pública del frontend:** `http://<dns-del-elb>.us-east-1.elb.amazonaws.com`  ← *completar con la URL real*

---

## 3. Clúster EKS

- **Clúster:** `innovatech-eks`, región `us-east-1`, Kubernetes 1.31.
- **Nodos:** node group administrado `ng-innovatech` con **2× `t3.medium`** (min 2, máx 3). Dos nodos
  porque deben coexistir MySQL, los dos backends Java, el frontend y los pods de sistema.
- **Roles IAM:** AWS Academy no permite crear roles IAM nuevos → se reutiliza **`LabRole`** como rol
  del clúster y de los nodos; OIDC desactivado por la misma razón.
- **Red:** VPC, subredes públicas/privadas (2 AZ) y Security Groups creados por **eksctl** vía
  CloudFormation.
- **Aprovisionamiento:** `eksctl` con el manifiesto declarativo `infra/eks-cluster.yaml`.

```bash
eksctl get cluster --region us-east-1
kubectl get nodes -o wide
aws eks describe-cluster --name innovatech-eks --region us-east-1 \
  --query "cluster.{rol:roleArn,vpc:resourcesVpcConfig.vpcId,sg:resourcesVpcConfig.securityGroupIds}"
```

> 📸 **Evidencia:** nodos Ready · consola EKS (Active) · node group con LabRole · subredes públicas/privadas etiquetadas · Security Groups.

---

## 4. Despliegue de servicios

Manifiestos declarativos en `infra/k8s/`, aplicados en orden: namespace → secret → MySQL → ventas →
despachos → frontend → HPA. Cada Deployment consume su imagen de **ECR** e inyecta variables de
entorno (`DB_ENDPOINT`, `DB_PORT`, `DB_NAME`) y credenciales desde el Secret.

| Archivo | Recurso |
|---|---|
| `00-namespace.yaml` | Namespace `innovatech` |
| `01-secrets.yaml` | Secret `db-secret` |
| `02-mysql.yaml` | Deployment + Service MySQL |
| `03-ventas.yaml` | Deployment + Service Ventas |
| `04-despachos.yaml` | Deployment + Service Despachos |
| `05-frontend.yaml` | Deployment + Service **LoadBalancer** Frontend |
| `06-hpa.yaml` | HPA de Ventas y Despachos |

```bash
kubectl get pods,svc,hpa -n innovatech
echo "http://$(kubectl get svc frontend-svc -n innovatech -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

> 📸 **Evidencia:** pods Running · services con EXTERNAL-IP · repos ECR con imágenes · frontend en el navegador.

---

## 5. Autoscaling (HPA)

HorizontalPodAutoscaler sobre CPU para `ventas` y `despachos`:

- **Umbral:** 50 % de CPU promedio. **Réplicas:** mín 1, máx 4. Requiere `metrics-server`.

**Justificación del 50 %:** margen para picos (escala antes de saturar), evita *flapping* (punto medio
estable) y acota el costo (máx 4).

```bash
kubectl get hpa -n innovatech
kubectl top pods -n innovatech
bash scripts/05-loadtest.sh      # genera carga para disparar el escalado
```

> 📸 **Evidencia:** HPA en reposo · HPA bajo carga (>50 %) · pods escalando 1→4 · evento SuccessfulRescale.

---

## 6. Pipeline CI/CD

Definido en `.github/workflows/deploy.yml`, se ejecuta ante cada `push` a `main`:

1. **Checkout** del código.
2. **Autenticación AWS** con credenciales temporales del laboratorio (GitHub Secrets).
3. **Login a ECR.**
4. **Build & push** de las 3 imágenes (tag = **SHA del commit** + `latest`).
5. **Conexión al clúster:** `aws eks update-kubeconfig`.
6. **Deploy:** `kubectl set image` + `kubectl rollout status` (falla el job si el rollout no converge).
7. **Estado final:** `kubectl get pods,svc,hpa`.

> 📸 **Evidencia:** corrida en verde (Actions) · paso build/push · paso deploy con rollout · imagen ECR con tag = SHA.

---

## 7. Secretos y credenciales

- **Base de datos:** `DB_USERNAME`/`DB_PASSWORD` en un `Secret` de Kubernetes (`db-secret`), inyectados
  vía `secretKeyRef`. Ningún valor sensible en el código ni en los Deployments.
- **AWS (pipeline):** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` como **GitHub
  Secrets**, nunca en el código.

```bash
kubectl describe secret db-secret -n innovatech   # muestra las claves, no los valores
```

> 📸 **Evidencia:** secret en k8s (sin valores) · `secretKeyRef` en el Deployment · GitHub Secrets ocultos.

---

## 8. Observabilidad

- **Logs de aplicación:** `kubectl logs deploy/<servicio> -n innovatech`.
- **Métricas:** `kubectl top pods -n innovatech` (metrics-server).
- **Pipeline:** tiempos y resultado en la pestaña Actions.
- **Infraestructura:** métricas de los nodos EC2 en CloudWatch.

> 📸 **Evidencia:** logs de los backends · `kubectl top pods` · tiempos del job en Actions.

---

## 9. Validación funcional y tolerancia a fallos

- **End-to-end:** crear venta → generar despacho → cerrar despacho, desde el frontend público.
- **Comunicación interna:** petición al Service por DNS interno responde **HTTP 200**.
- **Self-healing:** al borrar un pod, Kubernetes lo recrea; la app sigue disponible.

```bash
kubectl exec -n innovatech deploy/ventas -- \
  curl -s -o /dev/null -w "HTTP: %{http_code}\n" http://localhost:8080/api/v1/ventas
kubectl delete pod -n innovatech -l app=ventas
kubectl get pods -n innovatech -w
```

> 📸 **Evidencia:** flujo en el navegador · HTTP 200 · pod recreándose.

---

## 10. Problemas y soluciones

| # | Problema | Solución |
|---|---|---|
| 1 | Frontend con IPs de LAN fijas. | URLs relativas (`VITE_API_BASE`) + reverse proxy nginx. |
| 2 | Campo `entregado` vs `despachado`. | Modelo unificado a `despachado`. |
| 3 | Tests de contexto fallaban sin MySQL en el build. | Imagen construida con `-DskipTests`. |
| 4 | AWS Academy no permite crear roles IAM. | Reutilización de `LabRole`; OIDC off. |
| 5 | Credenciales del laboratorio caducan por sesión. | Renovación de GitHub Secrets (en prod: OIDC). |
| 6 | `metrics-server` sin métricas (HPA). | Reinstalación con `--kubelet-insecure-tls`. |

---

## 11. Estructura del repositorio

```
.
├── .github/workflows/deploy.yml      # Pipeline CI/CD
├── back-ventas-springboot/           # API Ventas + Dockerfile
├── back-bespachos-springboot/        # API Despachos + Dockerfile
├── front-despacho/                   # Frontend React + Dockerfile + nginx.conf
├── infra/
│   ├── eks-cluster.yaml              # Clúster (eksctl · IaC)
│   └── k8s/                          # Manifiestos Kubernetes (00..06)
├── scripts/                          # setup, ECR, build/push, deploy, carga
└── README.md
```

---

## 12. Cómo reproducir el despliegue

```bash
# 1) Credenciales del Learner Lab
aws configure set aws_access_key_id "..."
aws configure set aws_secret_access_key "..."
aws configure set aws_session_token "..."
aws configure set region us-east-1

# 2) Clúster EKS (reemplaza el Account ID del LabRole)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/533588032385/${ACCOUNT_ID}/g" infra/eks-cluster.yaml
eksctl create cluster -f infra/eks-cluster.yaml

# 3) Repos ECR + primera carga de imágenes
bash scripts/02-ecr-create.sh
bash scripts/03-build-push.sh latest

# 4) Despliegue en el clúster (renderiza <ACCOUNT_ID> automáticamente)
bash scripts/04-deploy.sh

# 5) URL pública
kubectl get svc frontend-svc -n innovatech \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# 6) Al finalizar, para no consumir saldo
eksctl delete cluster --name innovatech-eks --region us-east-1
```
