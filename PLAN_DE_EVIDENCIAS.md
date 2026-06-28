# Plan de captura de evidencias — EP3 InnovaTech

Guía para capturar **exactamente** la evidencia que pide cada indicador de la rúbrica.
Para cada captura: el comando o pantalla, qué debe verse, el nombre de archivo sugerido
y el pie de foto para tu README/presentación.

**Consejos generales antes de capturar:**
- Que se vea la **hora** del sistema y, en terminal, el prompt (demuestra que es real y reciente).
- En cada terminal, corre primero `aws sts get-caller-identity` una vez para dejar claro la cuenta.
- Guarda todo en una carpeta `evidencias/` dentro del repo, con estos nombres, y enlázalas en el README.
- Captura **antes y después** donde aplique (sobre todo en autoscaling).

---

## IE1 — Configuración del clúster AWS (EKS) — 25%

| # | Comando / Pantalla | Qué debe mostrar | Archivo |
|---|---|---|---|
| 1.1 | `eksctl get cluster --region us-east-1` | el clúster `innovatech-eks` listado | `ie1_eksctl_cluster.png` |
| 1.2 | `kubectl get nodes -o wide` | 2 nodos en estado **Ready**, con IPs y versión | `ie1_nodes_ready.png` |
| 1.3 | Consola AWS → **EKS → innovatech-eks → Overview** | estado **Active**, versión de K8s, VPC asociada | `ie1_eks_overview.png` |
| 1.4 | Consola AWS → **EKS → Compute → node group** | node group con instancias `t3.medium` y **LabRole** como Node IAM role | `ie1_nodegroup.png` |
| 1.5 | Consola AWS → **VPC → Subnets** (filtra por la VPC del clúster) | subredes creadas por eksctl en distintas AZ | `ie1_subnets.png` |
| 1.6 | `aws eks describe-cluster --name innovatech-eks --region us-east-1 --query "cluster.{rol:roleArn,vpc:resourcesVpcConfig.vpcId,sg:resourcesVpcConfig.securityGroupIds}"` | el `roleArn` = **LabRole**, el VPC y los Security Groups | `ie1_describe_cluster.png` |

**Pie de foto / texto:** "Clúster EKS `innovatech-eks` activo, 2 nodos `t3.medium` con `LabRole`,
VPC y subredes creadas por eksctl, Security Groups gestionados por EKS."

> Para defender IE1: explica que se reutiliza `LabRole` como rol del clúster **y** de los nodos
> porque Learner Lab no permite crear roles IAM nuevos.

---

## IE2 — Despliegue Frontend + Backend en el clúster — 25%

| # | Comando / Pantalla | Qué debe mostrar | Archivo |
|---|---|---|---|
| 2.1 | `kubectl get pods -n innovatech` | `frontend`, `ventas`, `despachos`, `mysql` todos **Running 1/1** | `ie2_pods_running.png` |
| 2.2 | `kubectl get svc -n innovatech` | backends `ClusterIP`, `frontend-svc` **LoadBalancer** con `EXTERNAL-IP` (DNS del ELB) | `ie2_services.png` |
| 2.3 | Consola AWS → **ECR** | los 3 repos (`innovatech-ventas/-despachos/-frontend`) con imágenes subidas | `ie2_ecr_repos.png` |
| 2.4 | `kubectl describe deployment ventas -n innovatech \| grep -A3 -E "Image\|Environment"` | la imagen viene de **ECR** y las variables de entorno (DB_*, con Secret) | `ie2_deploy_image_env.png` |
| 2.5 | Navegador → URL pública del frontend | la app cargada (la UI de despachos) | `ie2_frontend_publico.png` |
| 2.6 | Navegador con **DevTools → Network** abierto, recargando el frontend | la llamada a `/api/v1/ventas` devolviendo **200** (Front→Back OK) | `ie2_network_200.png` |

**Pie de foto:** "Frontend accesible por URL pública del balanceador; backends desplegados desde
ECR como servicios internos; comunicación Front→Back vía DNS interno verificada (HTTP 200)."

---

## IE3 — Configuración de Autoscaling (HPA) — 10%

> Necesitas **2 terminales**: una observando, otra generando carga (`scripts/05-loadtest.sh`).

| # | Comando / Pantalla | Qué debe mostrar | Archivo |
|---|---|---|---|
| 3.1 | `kubectl get hpa -n innovatech` (en reposo) | HPA con CPU bajo (ej. `2%/50%`) y `REPLICAS 1` | `ie3_hpa_reposo.png` |
| 3.2 | `cat infra/k8s/06-hpa.yaml` | el umbral **50%** y min/max (justificación) | `ie3_hpa_yaml.png` |
| 3.3 | Con carga activa: `kubectl get hpa -n innovatech` | CPU **por encima de 50%** (ej. `120%/50%`) | `ie3_hpa_carga.png` |
| 3.4 | Con carga activa: `kubectl get pods -n innovatech` | **más réplicas** de `ventas` (2, 3 o 4) | `ie3_pods_escalados.png` |
| 3.5 | `kubectl describe hpa ventas-hpa -n innovatech \| tail -15` | eventos `SuccessfulRescale` (subida de réplicas) | `ie3_hpa_events.png` |

**Pie de foto:** "HPA al 50% de CPU. Bajo carga el promedio supera el umbral y el autoscaler
escala `ventas` de 1 a N réplicas; los eventos `SuccessfulRescale` lo confirman."

> Justificación del 50% (para la defensa): da margen para absorber picos antes de saturar el pod
> y evita *flapping*; min=1 ahorra recursos en reposo, max=4 acota el costo en Learner Lab.

---

## IE4 — Pipeline CI/CD (build → push → deploy) — 15%

| # | Comando / Pantalla | Qué debe mostrar | Archivo |
|---|---|---|---|
| 4.1 | GitHub → pestaña **Actions** → la corrida | el workflow **verde**, todos los pasos OK | `ie4_pipeline_verde.png` |
| 4.2 | Paso **"Build & push de las 3 imágenes"** expandido | el `docker push` de las 3 imágenes con el tag = SHA | `ie4_build_push.png` |
| 4.3 | Paso **"Deploy"** expandido | `kubectl set image` + `rollout status ... successfully rolled out` | `ie4_deploy_rollout.png` |
| 4.4 | Consola AWS → **ECR → innovatech-ventas → Images** | una imagen con el tag = SHA del commit reciente | `ie4_ecr_tag_sha.png` |
| 4.5 | GitHub → el **commit** que disparó la corrida | el commit + su check verde | `ie4_commit_trigger.png` |

**Pie de foto:** "Pipeline en GitHub Actions: ante un `push` a `main` compila las 3 imágenes,
las publica en ECR (tag = SHA) y actualiza los Deployments con `rollout status` exitoso."

---

## IE5 — Gestión de Secrets y credenciales — 5%

| # | Comando / Pantalla | Qué debe mostrar | Archivo |
|---|---|---|---|
| 5.1 | `kubectl get secret db-secret -n innovatech` | el Secret existe, tipo **Opaque** | `ie5_secret_exists.png` |
| 5.2 | `kubectl describe secret db-secret -n innovatech` | las **claves** (DB_USERNAME, DB_PASSWORD...) **sin** mostrar los valores | `ie5_secret_keys.png` |
| 5.3 | `kubectl get deployment ventas -n innovatech -o yaml \| grep -A4 secretKeyRef` | el pod consume la credencial vía `secretKeyRef` (no en texto plano) | `ie5_secretkeyref.png` |
| 5.4 | GitHub → **Settings → Secrets and variables → Actions** | los 3 secretos AWS existen, valores ocultos | `ie5_github_secrets.png` |

**Pie de foto:** "Credenciales fuera del código: BD en un `Secret` de Kubernetes inyectado por
`secretKeyRef`; credenciales de AWS en *secrets* de GitHub. Ningún valor sensible en el repo."

> ⚠️ **No** muestres el valor real de las contraseñas en ninguna captura.

---

## IE6 — Análisis de logs, métricas y tiempos del pipeline — 10%

| # | Comando / Pantalla | Qué debe mostrar | Archivo |
|---|---|---|---|
| 6.1 | `kubectl logs deploy/ventas -n innovatech --tail=30` | el arranque de Spring Boot ("Started ... in X seconds") | `ie6_logs_ventas.png` |
| 6.2 | `kubectl logs deploy/despachos -n innovatech --tail=30` | arranque del backend de despachos | `ie6_logs_despachos.png` |
| 6.3 | `kubectl top pods -n innovatech` | uso de **CPU/memoria** por pod (métricas) | `ie6_top_pods.png` |
| 6.4 | GitHub → Actions → la corrida (vista de duración) | duración total y por paso (build vs deploy) | `ie6_pipeline_tiempos.png` |

**Texto a redactar (tabla en el README):** total del job, build vs deploy, fallos/reintentos,
y una conclusión corta (ej. "el build domina el tiempo; el deploy es < X s").

---

## IE7 — Validación funcional del clúster (Front → Back) — 10%

| # | Comando / Pantalla | Qué debe mostrar | Archivo |
|---|---|---|---|
| 7.1 | Navegador: crear una **venta** (Swagger por port-forward o UI) | la venta creada (respuesta 200/201) | `ie7_crear_venta.png` |
| 7.2 | Navegador: **Generar Despacho** desde el frontend | el SweetAlert "Despacho registrado" | `ie7_generar_despacho.png` |
| 7.3 | Navegador: **Cerrar despacho** | el despacho marcado como entregado | `ie7_cerrar_despacho.png` |
| 7.4 | `kubectl exec -n innovatech deploy/frontend -- wget -qO- http://ventas-svc:8080/api/v1/ventas` | respuesta JSON → prueba la comunicación interna por DNS | `ie7_dns_interno.png` |
| 7.5 | `kubectl delete pod -n innovatech -l app=ventas` y luego `kubectl get pods -n innovatech -w` | el pod borrado y **uno nuevo recreándose** (self-healing) | `ie7_self_healing.png` |
| 7.6 | Tras el redeploy, recargar el frontend | la app **sigue funcionando** | `ie7_post_redeploy.png` |

**Pie de foto:** "Flujo end-to-end venta→despacho→cierre operativo; comunicación interna por DNS
verificada; recuperación automática del pod tras eliminarlo (self-healing) y disponibilidad
mantenida post-redeploy."

---

## Checklist final (marca cuando tengas cada una)

- [ ] IE1: 1.1–1.6 (clúster, nodos, VPC, roles)
- [ ] IE2: 2.1–2.6 (pods, services, ECR, frontend público, Front→Back)
- [ ] IE3: 3.1–3.5 (HPA reposo, yaml, carga, escalado, eventos)
- [ ] IE4: 4.1–4.5 (pipeline verde, build/push, deploy, ECR tag, commit)
- [ ] IE5: 5.1–5.4 (secret k8s, keys, secretKeyRef, github secrets)
- [ ] IE6: 6.1–6.4 (logs x2, top, tiempos pipeline) + tabla escrita
- [ ] IE7: 7.1–7.6 (flujo, DNS interno, self-healing, post-redeploy)

> Orden recomendado de captura en una sola sesión de lab:
> crear clúster → IE1 → deploy → IE2 → IE5 → IE7 (flujo + self-healing) →
> IE3 (carga) → IE6 (logs/top) → push para disparar pipeline → IE4 + tiempos de IE6.
> Captura todo **antes** de borrar el clúster.
