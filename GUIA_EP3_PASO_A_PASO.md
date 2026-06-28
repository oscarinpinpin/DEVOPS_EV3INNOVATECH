# Guía paso a paso — EP3 InnovaTech (EKS + CI/CD)

> Orquestación y automatización en AWS para el proyecto InnovaTech
> (2 backends Spring Boot + 1 frontend React) usando **WSL2, Docker, AWS CLI y kubectl**.
> Todo pensado para **AWS Academy Learner Lab**, que tiene restricciones que esta guía resuelve.

---

## 0. Qué vas a construir (la arquitectura, en una frase)

Un clúster **EKS** con: una base **MySQL** interna, los dos backends (**ventas** :8080 y **despachos** :8081) como servicios internos, y un **frontend** (React servido por nginx) expuesto con un **balanceador público**. El frontend nginx hace de **reverse proxy** hacia los backends por **DNS interno** del clúster. Un **pipeline de GitHub Actions** compila las imágenes, las sube a **ECR** y actualiza los Deployments. El **autoscaling** lo da un **HPA** sobre CPU.

```
                 Internet
                    │
          ┌─────────▼──────────┐   (Service type LoadBalancer => ELB público)
          │   frontend (nginx) │
          │  sirve React +     │
          │  proxy /api/...     │
          └───┬───────────┬────┘
   /api/v1/ventas    /api/v1/despachos     (DNS interno del clúster)
              │           │
        ┌─────▼───┐  ┌────▼──────┐
        │ ventas  │  │ despachos │   (ClusterIP, NO públicos)
        │  :8080  │  │   :8081   │
        └────┬────┘  └────┬──────┘
             └─────┬──────┘
              ┌────▼────┐
              │  mysql  │  (ClusterIP headless)
              │  :3306  │
              └─────────┘
```

**Por qué así (esto lo defiendes en la presentación):**
- El frontend es el único expuesto → menos superficie de ataque. Los backends y la BD son internos.
- nginx proxea `/api/...` al backend correcto → **no hay problemas de CORS** (todo es el mismo origen) y **no hay que recompilar** el frontend si cambia la URL del balanceador.
- Comunicación Front → Back por **DNS interno** (`ventas-svc`, `despachos-svc`) → cumple el indicador IE2/IE7 de la rúbrica.

---

## 1. Preparar el entorno (WSL2 + Docker + herramientas)

### 1.1 WSL2
En PowerShell (como administrador), en tu PC con Windows:
```powershell
wsl --install -d Ubuntu
wsl --set-default-version 2
```
Reinicia si te lo pide. Abre **Ubuntu** desde el menú inicio y crea tu usuario.

Verifica que estás en WSL **2**:
```powershell
wsl -l -v      # la columna VERSION debe decir 2
```

### 1.2 Docker Desktop
Instala **Docker Desktop** en Windows y activa la integración con WSL2:
`Settings → Resources → WSL Integration → activa tu distro Ubuntu`.
Dentro de Ubuntu, confirma:
```bash
docker version
docker run --rm hello-world
```

### 1.3 AWS CLI, kubectl y eksctl
Desde Ubuntu (WSL2), corre el script incluido:
```bash
bash scripts/01-setup-wsl-tools.sh
```
Esto instala **AWS CLI v2**, **kubectl** y **eksctl**. Verifica:
```bash
aws --version
kubectl version --client
eksctl version
```

### 1.4 Credenciales de AWS Academy (Learner Lab)
1. Entra al **Learner Lab**, presiona **Start Lab** y espera el círculo verde.
2. Clic en **AWS Details → AWS CLI → Show**. Verás algo como:
   ```
   aws_access_key_id=ASIA...
   aws_secret_access_key=...
   aws_session_token=...
   ```
3. En Ubuntu, pega ese bloque dentro de `~/.aws/credentials`:
   ```bash
   mkdir -p ~/.aws
   nano ~/.aws/credentials
   ```
   Pégalo bajo el encabezado `[default]`:
   ```ini
   [default]
   aws_access_key_id=ASIA...
   aws_secret_access_key=...
   aws_session_token=...
   ```
   Y crea `~/.aws/config`:
   ```ini
   [default]
   region=us-east-1
   output=json
   ```
4. Verifica:
   ```bash
   aws sts get-caller-identity
   ```
   Te devuelve tu `Account` y un ARN tipo `assumed-role/voclabs/...`.

> ⚠️ **Estas credenciales caducan** cuando se acaba el tiempo del lab (~4 h) o reinicias.
> Cuando vuelvas, **vuelve a copiar el bloque** a `~/.aws/credentials`. Es la causa #1 de errores "ExpiredToken".

---

## 2. Preparar el repositorio (monorepo)

La rúbrica pide **un monorepo** en GitHub con README y commits explicativos. Copia el contenido de este kit sobre tu repo base, quedando así:

```
innovatech/
├── back-ventas-springboot/api-rest-ventas/      (+ Dockerfile)
├── back-bespachos-springboot/api-rest-despacho/ (+ Dockerfile)
├── front-despacho/                              (+ Dockerfile, nginx.conf)
├── infra/
│   ├── eks-cluster.yaml
│   └── k8s/  (00..06 .yaml)
├── scripts/  (01..05 .sh)
├── .github/workflows/deploy.yml
└── README.md
```

### 2.1 Aplicar los arreglos del frontend (obligatorio)
El frontend original apunta a IPs LAN inexistentes (`192.168.30`, `192.168.320`, etc.). **No funciona** así. Reemplaza estos 4 archivos por los de `patches/front/`:

```bash
cp patches/front/TableCompras.jsx      front-despacho/src/componentes/CrudAdmin/
cp patches/front/TableDespachos.jsx    front-despacho/src/componentes/CrudAdmin/
cp patches/front/FormDespacho.jsx      front-despacho/src/componentes/CrudAdmin/
cp patches/front/FormCierreDespacho.jsx front-despacho/src/componentes/CrudAdmin/
```

Qué cambiaron (para que lo expliques):
- Las URLs ahora son **relativas** (`/api/v1/ventas`), así que el navegador llama al **mismo host** del frontend y nginx las proxea. Adiós IPs hardcodeadas y adiós CORS.
- Se corrigió el bug `entregado` → `despachado` (la entidad del backend usa `despachado`; el front leía un campo que no existía y siempre mostraba "pendiente").

### 2.2 Commit
Haz commits **pequeños y explicativos** (la rúbrica los evalúa):
```bash
git add .
git commit -m "fix(front): URLs relativas + campo despachado; feat: Dockerfiles, k8s, CI/CD"
git push origin main
```

---

## 3. Crear el clúster EKS

### 3.1 Poner tu Account ID en el config de eksctl
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" infra/eks-cluster.yaml
```

> **Por qué reutilizamos `LabRole`:** en Learner Lab **no puedes crear roles IAM**. Solo existe `LabRole`, que ya trae los permisos de EKS. Por eso el config lo usa como rol del clúster y de los nodos, y desactiva OIDC (que requeriría crear un proveedor IAM).

### 3.2 Crear el clúster (tarda ~15-20 min)
```bash
eksctl create cluster -f infra/eks-cluster.yaml
```
Cuando termine, kubectl ya queda apuntando al clúster. Verifica:
```bash
kubectl get nodes        # deberías ver 2 nodos en estado Ready
```

> **Si `eksctl` falla por permisos IAM** (p. ej. `not authorized to perform iam:CreateInstanceProfile`):
> usa la **Consola web** como plan B → servicio **EKS → Add cluster → Create**, eligiendo `LabRole`
> como *Cluster service role*, y luego **Add node group** eligiendo `LabRole` como *Node IAM role*.
> Después conecta kubectl con:
> `aws eks update-kubeconfig --name innovatech-eks --region us-east-1`

### 3.3 Verificar el acceso (auth)
```bash
kubectl auth can-i '*' '*'      # debería responder: yes
```
Si te sale **"Unauthorized"**, es porque kubectl usa una identidad distinta a la que creó el clúster. Solución rápida (mismo lab, mismas credenciales) suele bastar; si persiste, crea un *access entry* para tu rol:
```bash
aws eks create-access-entry --cluster-name innovatech-eks \
  --principal-arn $(aws sts get-caller-identity --query Arn --output text | sed 's#assumed-role/\([^/]*\)/.*#role/\1#') \
  --region us-east-1 || true
```

---

## 4. Crear los repositorios ECR y la primera carga de imágenes

### 4.1 Crear los repos
```bash
bash scripts/02-ecr-create.sh
```
Crea `innovatech-ventas`, `innovatech-despachos`, `innovatech-frontend`.

### 4.2 Primera build + push manual
Antes de tener el pipeline funcionando conviene subir las imágenes una vez a mano (así el `kubectl apply` del paso 5 ya encuentra imágenes):
```bash
bash scripts/03-build-push.sh latest
```
Esto compila los 2 backends (Maven dentro del contenedor, **sin tests** para evitar el fallo conocido de los context-tests que piden MySQL) y el frontend (Vite → nginx), y los empuja a ECR.

---

## 5. Desplegar la aplicación en el clúster

```bash
bash scripts/04-deploy.sh
```
El script:
1. Instala **metrics-server** (lo necesita el HPA).
2. Reemplaza `<ACCOUNT_ID>` en los manifiestos.
3. Aplica en orden: namespace → secret → mysql → ventas → despachos → frontend → hpa.
4. Te muestra pods, services y el **DNS público** del frontend.

Verifica que todo quede `Running`:
```bash
kubectl get pods -n innovatech
```

Obtén la URL pública (puede tardar 2-3 min en provisionarse el balanceador):
```bash
kubectl get svc frontend-svc -n innovatech \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```
Ábrela en el navegador: deberías ver el frontend. (Si la BD está vacía, las tablas saldrán vacías; usa Swagger para crear una venta de prueba, ver paso 7.)

> Si `metrics-server` no entrega métricas (`kubectl top` falla), edita su deployment y añade
> el flag `--kubelet-insecure-tls`:
> `kubectl -n kube-system edit deployment metrics-server` (en `args:` agrega esa línea).

---

## 6. Pipeline CI/CD con GitHub Actions

El archivo `.github/workflows/deploy.yml` hace **build → push → deploy** en cada `push` a `main`.

### 6.1 Cargar los secretos del repo
En GitHub: **Settings → Secrets and variables → Actions → New repository secret**. Crea estos 3 con los valores de **AWS Details → AWS CLI** del Learner Lab:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

> ⚠️ **Cada vez que reinicies el lab** estos 3 valores cambian → actualízalos antes de correr el pipeline,
> o el job fallará con error de credenciales. (Esto es perfecto para la sección "Problemas encontrados" del README:
> en producción real se usaría OIDC/roles, pero Learner Lab no permite crearlos.)

### 6.2 Probar el despliegue automático
Haz un cambio mínimo (por ejemplo en el README o un texto del frontend), commit y push:
```bash
git commit -am "test: disparar pipeline CI/CD"
git push origin main
```
Ve a la pestaña **Actions** del repo y observa el job. Al terminar, el rollout deja la nueva versión corriendo. **Captura esto** (el log del pipeline) para la evidencia.

---

## 7. Validación funcional, logs y métricas (evidencia para la rúbrica)

### 7.1 Crear datos de prueba (Swagger)
Como el frontend lee de la BD, primero crea una venta. Puedes hacer port-forward al backend y usar Swagger:
```bash
kubectl -n innovatech port-forward svc/ventas-svc 8080:8080
# en el navegador: http://localhost:8080/swagger-ui.html  -> POST /api/v1/ventas
```
Crea una venta (dirección, fecha, `despachoGenerado:false`). Luego recarga el frontend: aparecerá en "Generar Despacho". Con eso demuestras el flujo **venta → despacho → cierre** (Front → ventas y Front → despachos).

### 7.2 Logs
```bash
kubectl logs -n innovatech deploy/ventas --tail=50
kubectl logs -n innovatech deploy/despachos --tail=50
kubectl logs -n innovatech deploy/frontend --tail=50
```
(En EKS estos logs también pueden enviarse a CloudWatch con el addon Fluent Bit; para la rúbrica, `kubectl logs` es suficiente y es lo que pide explícitamente IE6.)

### 7.3 Autoscaling (HPA) en vivo
En una terminal observa, en otra genera carga:
```bash
# Terminal A (observar):
kubectl get hpa -n innovatech -w
kubectl get pods -n innovatech -w

# Terminal B (carga):
bash scripts/05-loadtest.sh
```
Verás subir el `%CPU` y, al pasar el 50%, el HPA aumenta las réplicas de `ventas` (hasta 4). Al cortar la carga, baja de nuevo (tarda unos minutos por la política de *cooldown*). **Captura** el antes/después de `kubectl get hpa` y `kubectl get pods`.

### 7.4 Recuperación ante fallo (self-healing)
Borra un pod y mira cómo Kubernetes lo recrea solo:
```bash
kubectl delete pod -n innovatech -l app=ventas
kubectl get pods -n innovatech -w     # aparece uno nuevo en segundos
```
Esto evidencia "tolerancia a fallos / recuperación post-deploy" (IE7).

### 7.5 Métricas y tiempos del pipeline (IE6)
Anota de la pestaña **Actions**: duración total del job, duración de build vs deploy, y si hubo fallos. Eso va al README en la sección de métricas.

---

## 8. Qué entregar y cómo prepararte para la defensa

**Entrega (AVA):** el monorepo en GitHub con:
- Código + Dockerfiles + `infra/` + `.github/workflows/` + `README.md`.
- Commits explicativos.
- README con: arquitectura, roles/redes/autoscaling/balanceador, métricas del pipeline, y problemas encontrados. (Plantilla lista en `README_EP3.md`.)

**La presentación es 80% individual** — debes poder explicar **cada decisión**. Repasa:
- Por qué EKS y no ECS (te pidieron kubectl → Kubernetes → EKS).
- Por qué `LabRole` para todo (no se pueden crear roles en Learner Lab).
- Por qué el frontend hace de proxy (CORS, no recompilar, DNS interno).
- Por qué HPA al 50% de CPU (margen para picos, sin flapping).
- Por qué Secrets de Kubernetes para la BD (IE5: credenciales fuera del código).
- Limitación honesta: MySQL con `emptyDir` no persiste si su pod muere (mejora: PVC + EBS CSI).
- Limitación honesta: secretos AWS estáticos en GitHub porque Learner Lab no permite OIDC.

---

## 9. Apagar para no gastar saldo

Al terminar cada sesión, **borra el clúster** (el balanceador y los nodos cuestan):
```bash
eksctl delete cluster --name innovatech-eks --region us-east-1
```
Si dejaste el `frontend-svc` (LoadBalancer), bórralo antes para que se elimine el ELB:
```bash
kubectl delete svc frontend-svc -n innovatech
```

---

## 10. Tabla rápida de problemas comunes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `ExpiredToken` / `InvalidClientTokenId` | credenciales del lab caducaron | re-copia el bloque de AWS CLI a `~/.aws/credentials` |
| `kubectl ... Unauthorized` | identidad distinta a la que creó el clúster | mismo lab/credenciales; o crear *access entry* (paso 3.3) |
| `eksctl` falla por `iam:Create...` | Learner Lab bloquea IAM | crear clúster/nodegroup por la **Consola** con `LabRole` (paso 3.2) |
| Pods en `Pending` | nodos sin recursos | sube a `t3.large` o `maxSize: 3` en `eks-cluster.yaml` |
| Pod backend `CrashLoopBackOff` | no conecta a MySQL | revisa `kubectl logs`; que el Secret y `mysql-svc` existan |
| `kubectl top` sin datos | metrics-server sin TLS | añade `--kubelet-insecure-tls` (paso 5) |
| Frontend carga pero API falla | nginx no resuelve el backend | confirma nombres `ventas-svc`/`despachos-svc` y que estén `Running` |
| ELB sin DNS | aún provisionando | espera 2-3 min y reintenta el `kubectl get svc` |

---

### Resumen de comandos (orden completo)
```bash
bash scripts/01-setup-wsl-tools.sh
# (configurar ~/.aws/credentials con el bloque del lab)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" infra/eks-cluster.yaml
eksctl create cluster -f infra/eks-cluster.yaml
bash scripts/02-ecr-create.sh
bash scripts/03-build-push.sh latest
bash scripts/04-deploy.sh
# (cargar secretos en GitHub y push para probar el pipeline)
# (validar: logs, HPA con scripts/05-loadtest.sh, self-healing)
eksctl delete cluster --name innovatech-eks --region us-east-1   # al terminar
```
