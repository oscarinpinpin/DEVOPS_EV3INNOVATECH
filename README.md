# DEVOPS EP3 — Orquestación y Automatización de InnovaTech en Amazon EKS

Despliegue productivo del sistema de despachos **InnovaTech** sobre un clúster **Amazon EKS**,
con entrega continua mediante **GitHub Actions** (build → push a ECR → deploy) y **escalado
automático horizontal (HPA)**. El proyecto orquesta una aplicación de microservicios compuesta
por dos APIs REST en Spring Boot, un frontend en React y una base de datos MySQL, garantizando
escalabilidad, tolerancia a fallos, balanceo de carga y despliegue automatizado.

**Asignatura:** Introducción a Herramientas DevOps (ISY1101)
**Evaluación:** Parcial N°3 — Encargo con Presentación

## Integrantes
- Oscar Báez
- Benjamín Araya

---

## Índice
1. [Contexto y objetivos](#1-contexto-y-objetivos)
2. [Arquitectura final](#2-arquitectura-final)
3. [Configuración del clúster EKS](#3-configuración-del-clúster-eks)
4. [Despliegue de servicios (Frontend + Backend)](#4-despliegue-de-servicios)
5. [Configuración de Autoscaling (HPA)](#5-configuración-de-autoscaling-hpa)
6. [Pipeline CI/CD](#6-pipeline-cicd)
7. [Gestión de Secrets y credenciales](#7-gestión-de-secrets-y-credenciales)
8. [Logs, métricas y tiempos](#8-logs-métricas-y-tiempos)
9. [Validación funcional y tolerancia a fallos](#9-validación-funcional-y-tolerancia-a-fallos)
10. [Problemas encontrados y soluciones](#10-problemas-encontrados-y-soluciones)
11. [Estructura del repositorio](#11-estructura-del-repositorio)
12. [Cómo reproducir el despliegue](#12-cómo-reproducir-el-despliegue)

---

## 1. Contexto y objetivos

InnovaTech, tras contenedorizar su aplicación (EP2) y montar infraestructura base en AWS (EP1),
avanza hacia la automatización y orquestación productiva. Los objetivos de esta etapa son:

- Ejecutar la aplicación de forma **escalable, tolerante a fallos y automatizable**.
- **Automatizar completamente** los despliegues desde GitHub mediante GitHub Actions.
- Garantizar que la aplicación pueda **escalar, autorrecuperarse, registrar logs, balancearse
  y mantenerse disponible** ante cambios o fallos.
- Utilizar **EKS** como plataforma de orquestación (Kubernetes), operada con `kubectl`.

---

## 2. Arquitectura final

```
                          Internet
                             │
                ┌────────────▼─────────────┐   Service type LoadBalancer
                │     frontend (nginx)      │   → ELB público de AWS
                │  SPA React + reverse proxy │
                └───┬──────────────────┬────┘
        /api/v1/ventas          /api/v1/despachos     (DNS interno del clúster)
                   │                  │
            ┌──────▼─────┐     ┌──────▼───────┐
            │   ventas    │     │   despachos  │       Service ClusterIP
            │ Spring Boot │     │ Spring Boot  │       (no expuestos a Internet)
            │   :8080     │     │    :8081     │
            └──────┬──────┘     └──────┬───────┘
                   └────────┬──────────┘
                     ┌──────▼──────┐
                     │    mysql     │   Service ClusterIP
                     │ ventasdb /   │   (interno)
                     │ despachosdb  │
                     └─────────────┘
```

**Justificación de la arquitectura (decisiones de diseño):**

- **El frontend es el único componente expuesto.** Reduce la superficie de ataque: los backends
  y la base de datos quedan accesibles solo dentro del clúster (`ClusterIP`).
- **nginx actúa como reverse proxy.** Sirve el SPA y redirige `/api/v1/ventas` → `ventas-svc` y
  `/api/v1/despachos` → `despachos-svc`. Esto elimina los problemas de CORS (todo es el mismo
  origen) y evita recompilar el frontend cuando cambia la URL del balanceador.
- **Comunicación Front → Back por DNS interno.** El frontend resuelve los servicios por nombre
  (`ventas-svc`, `despachos-svc`) usando el DNS interno de Kubernetes (CoreDNS).
- **Base de datos interna.** MySQL se ejecuta como un Deployment dentro del clúster, con dos
  esquemas (`ventasdb`, `despachosdb`), uno por backend.

| Componente | Tecnología | Puerto | Service | Acceso |
|---|---|---|---|---|
| Frontend | React + Vite + nginx | 80 | LoadBalancer | Público (ELB) |
| API Ventas | Spring Boot 3.4.4 / Java 17 | 8080 | ClusterIP | Interno |
| API Despachos | Spring Boot 3.4.4 / Java 17 | 8081 | ClusterIP | Interno |
| Base de datos | MySQL 8 | 3306 | ClusterIP | Interno |

URL pública del frontend: `TODO http://<dns-del-elb>.us-east-1.elb.amazonaws.com`

---

## 3. Configuración del clúster EKS

> **Indicador IE1.** Creación del clúster, nodos/capacity providers, VPC/subredes/SG, roles IAM
> y justificación de la arquitectura.

- **Clúster:** `innovatech-eks`, región `us-east-1`, Kubernetes v1.31.
- **Nodos:** node group **administrado** (`ng-innovatech`) con **2 instancias `t3.medium`**
  (mín 2, máx 3). Se eligieron 2 nodos porque deben coexistir MySQL, los dos backends Java, el
  frontend y los pods de sistema de Kubernetes; un solo nodo resultaría insuficiente.
- **Roles IAM:** AWS Academy (Learner Lab) **no permite crear roles IAM nuevos**, por lo que se
  reutiliza el rol existente **`LabRole`** como rol de servicio del clúster (`serviceRoleARN`) y
  como rol de los nodos (`instanceRoleARN`). OIDC se mantiene desactivado por la misma razón.
- **Red:** la VPC, las subredes (públicas y privadas en dos zonas de disponibilidad) y los
  Security Groups son creados y administrados por **eksctl** vía CloudFormation.
- **Herramienta de aprovisionamiento:** `eksctl` con el archivo declarativo `infra/eks-cluster.yaml`.

Comandos de verificación:
```bash
eksctl get cluster --region us-east-1
kubectl get nodes -o wide
kubectl auth can-i '*' '*'
aws eks describe-cluster --name innovatech-eks --region us-east-1 \
  --query "cluster.{rol:roleArn,vpc:resourcesVpcConfig.vpcId,sg:resourcesVpcConfig.securityGroupIds}"
```

`TODO insertar capturas: nodos Ready, consola EKS (estado Active), node group con LabRole, subredes/SG.`

---

## 4. Despliegue de servicios

> **Indicador IE2.** Servicios desplegados desde ECR, variables de entorno, balanceador, URL
> pública y comunicación Front → Back.

El despliegue se realiza con manifiestos declarativos de Kubernetes (`infra/k8s/`), aplicados en
orden: namespace → secret → MySQL → ventas → despachos → frontend → HPA.

- **Imágenes desde Amazon ECR:** cada Deployment consume su imagen del registro privado ECR
  (`<account>.dkr.ecr.us-east-1.amazonaws.com/innovatech-<servicio>`).
- **Variables de entorno:** los backends reciben `DB_ENDPOINT`, `DB_PORT`, `DB_NAME`, y las
  credenciales `DB_USERNAME` / `DB_PASSWORD` (estas últimas desde un Secret).
- **Balanceador:** el Service `frontend-svc` de tipo `LoadBalancer` provisiona automáticamente un
  ELB de AWS con DNS público.
- **Acceso público:** el frontend queda accesible por la URL del ELB.
- **Comunicación Front → Back:** verificada por DNS interno (ver sección 9).

Manifiestos:
| Archivo | Recurso |
|---|---|
| `00-namespace.yaml` | Namespace `innovatech` |
| `01-secrets.yaml` | Secret `db-secret` |
| `02-mysql.yaml` | Deployment + Service MySQL |
| `03-ventas.yaml` | Deployment + Service Ventas |
| `04-despachos.yaml` | Deployment + Service Despachos |
| `05-frontend.yaml` | Deployment + Service LoadBalancer Frontend |
| `06-hpa.yaml` | HPA de Ventas y Despachos |

```bash
kubectl get pods,svc,hpa -n innovatech
echo "http://$(kubectl get svc frontend-svc -n innovatech -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

`TODO insertar capturas: pods Running, services con EXTERNAL-IP, repos ECR, frontend en el navegador.`

---

## 5. Configuración de Autoscaling (HPA)

> **Indicador IE3.** Autoscaling configurado, métricas funcionando y justificación del umbral.

Se configuró un **HorizontalPodAutoscaler** sobre uso de CPU para los backends `ventas` y
`despachos`:

- **Umbral:** 50 % de CPU promedio.
- **Réplicas:** mínimo 1, máximo 4.
- **Requisito:** `metrics-server` activo para entregar métricas de CPU.

**Justificación del umbral del 50 %:** otorga margen para absorber picos de tráfico antes de
saturar el pod (no se espera al 100 % de CPU para escalar), evita el *flapping* (oscilación
constante de réplicas) al ser un punto medio estable, y acota el costo en el laboratorio con un
máximo de 4 réplicas.

Validación bajo carga: al generar tráfico sostenido contra el backend, el uso de CPU supera el
50 % y el HPA incrementa las réplicas de 1 hasta 4; al cesar la carga, vuelve a reducirlas.

```bash
kubectl get hpa -n innovatech
kubectl top pods -n innovatech
# Generación de carga: bash scripts/05-loadtest.sh
```

`TODO insertar capturas: HPA en reposo, HPA bajo carga (>50%), pods escalados, eventos SuccessfulRescale.`

---

## 6. Pipeline CI/CD

> **Indicador IE4.** Pipeline automatizado build → push → deploy, funcional y documentado.

Definido en `.github/workflows/deploy.yml`, se ejecuta ante cada `push` a la rama `main`:

1. **Checkout** del código.
2. **Autenticación AWS** con credenciales temporales del laboratorio.
3. **Login a Amazon ECR.**
4. **Build & push** de las tres imágenes (etiqueta = SHA del commit, además de `latest`).
5. **Conexión al clúster:** `aws eks update-kubeconfig`.
6. **Deploy:** `kubectl set image` por Deployment + `kubectl rollout status` (falla el job si el
   rollout no converge).
7. **Estado final:** `kubectl get pods,svc,hpa`.

Esto permite que un commit en `main` llegue a producción de forma automática, sin intervención
manual.

`TODO insertar capturas: corrida en verde (Actions), paso build/push, paso deploy con rollout, imagen ECR con tag = SHA.`

---

## 7. Gestión de Secrets y credenciales

> **Indicador IE5.** Secrets correctamente utilizados, seguros y sin exposición.

- **Base de datos:** las credenciales (`DB_USERNAME`, `DB_PASSWORD`) se almacenan en un `Secret`
  de Kubernetes (`db-secret`) y se inyectan en los pods mediante `secretKeyRef`. Ningún valor
  sensible aparece en el código ni en los manifiestos de Deployment.
- **AWS (pipeline):** las credenciales temporales se guardan como *secrets* del repositorio en
  GitHub (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`), nunca en el código.

```bash
kubectl get secret db-secret -n innovatech
kubectl describe secret db-secret -n innovatech   # muestra las claves, no los valores
```

`TODO insertar capturas: secret en k8s (sin valores), secretKeyRef en el Deployment, secrets de GitHub ocultos.`

---

## 8. Logs, métricas y tiempos

> **Indicador IE6.** Análisis de logs, errores, tiempos y métricas con conclusiones.

- **Logs de aplicación:** se consultan con `kubectl logs` (arranque de Spring Boot, errores,
  conexión a la base de datos).
- **Métricas de consumo:** `kubectl top` reporta CPU y memoria por pod (provistas por
  metrics-server).
- **Tiempos del pipeline:** registrados desde la pestaña Actions de GitHub.

```bash
kubectl logs deploy/ventas -n innovatech --tail=30
kubectl logs deploy/despachos -n innovatech --tail=30
kubectl top pods -n innovatech
```

### Métricas del pipeline
| Métrica | Valor |
|---|---|
| Duración total del job | TODO |
| Build (3 imágenes) | TODO |
| Deploy (rollouts) | TODO |
| Fallos / reintentos | TODO |

**Conclusión del análisis:** `TODO (ej.: el tiempo del pipeline está dominado por el build de las
imágenes; el deploy es de pocos segundos. Los backends tardan ~40-60 s en quedar listos por el
arranque de la JVM y la espera a la base de datos).`

`TODO insertar capturas: logs de los backends, kubectl top pods, tiempos del job en Actions.`

---

## 9. Validación funcional y tolerancia a fallos

> **Indicador IE7.** Servicios operativos, comunicación correcta, endpoints, logs y recuperación
> post-deploy.

- **Flujo funcional end-to-end:** creación de una venta → generación de despacho → cierre del
  despacho, operando desde el frontend público.
- **Comunicación interna (Front → Back):** verificada ejecutando una petición desde el pod del
  frontend (o del backend) hacia el Service por DNS interno; responde **HTTP 200**.
- **Self-healing:** al eliminar manualmente un pod, Kubernetes lo recrea automáticamente, ya que
  el Deployment mantiene el número de réplicas deseado. La aplicación permanece disponible.
- **Recuperación post-deploy:** tras una actualización (rollout) la aplicación sigue respondiendo.

```bash
# Comunicación interna (HTTP 200)
kubectl exec -n innovatech deploy/ventas -- \
  curl -s -o /dev/null -w "HTTP: %{http_code}\n" http://localhost:8080/api/v1/ventas

# Self-healing
kubectl delete pod -n innovatech -l app=ventas
kubectl get pods -n innovatech -w
```

`TODO insertar capturas: flujo en el navegador, HTTP 200, pod recreándose (self-healing).`

---

## 10. Problemas encontrados y soluciones

| # | Problema | Solución |
|---|---|---|
| 1 | Frontend con direcciones IP de LAN fijas (no conectaba a los backends). | URLs relativas + reverse proxy nginx. |
| 2 | Inconsistencia de campo entre frontend y backend (`entregado` vs `despachado`). | Se unificó el modelo de datos a `despachado`. |
| 3 | Los tests de contexto fallaban sin MySQL durante el build de imagen. | La imagen se construye con `-DskipTests`. |
| 4 | AWS Academy no permite crear roles IAM. | Reutilización de `LabRole`; OIDC desactivado. |
| 5 | `eksctl` fallaba por *cross-account pass role*. | Se corrigió el Account ID del LabRole en el manifiesto. |
| 6 | Credenciales temporales del laboratorio caducan cada sesión. | Se renuevan los secrets de GitHub por sesión (en producción se usaría OIDC). |
| 7 | `metrics-server` no entregaba métricas (`MissingEndpoints`). | Reinstalación + parámetro `--kubelet-insecure-tls`. |
| 8 | Docker en WSL2 fallaba al guardar credenciales (`docker-credential-desktop.exe`). | Se eliminó `credsStore` de `~/.docker/config.json`. |

---

## 11. Estructura del repositorio

```
.
├── .github/workflows/deploy.yml      # Pipeline CI/CD
├── back-ventas-springboot/           # API Ventas + Dockerfile
├── back-bespachos-springboot/        # API Despachos + Dockerfile
├── front-despacho/                   # Frontend React + Dockerfile + nginx.conf
├── infra/
│   ├── eks-cluster.yaml              # Definición del clúster (eksctl)
│   └── k8s/                          # Manifiestos de Kubernetes (00..06)
├── scripts/                          # Automatización (setup, ECR, build/push, deploy, carga)
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
sed -i "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" infra/eks-cluster.yaml
eksctl create cluster -f infra/eks-cluster.yaml

# 3) Repositorios ECR + imágenes
bash scripts/02-ecr-create.sh
bash scripts/03-build-push.sh latest

# 4) Despliegue en el clúster
bash scripts/04-deploy.sh

# 5) URL pública
kubectl get svc frontend-svc -n innovatech \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# 6) Al finalizar, para no consumir saldo
kubectl delete svc frontend-svc -n innovatech
eksctl delete cluster --name innovatech-eks --region us-east-1
```
