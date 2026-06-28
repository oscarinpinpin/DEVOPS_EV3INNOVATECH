# FINDINGS.md — Reporte de revisión del proyecto InnoTech Despacho

> Revisión estática del código realizada el 2026-06-23 sobre el workspace
> `C:\Users\javi\Code\work\duoc\intro-devops\innovatech\proyecto semestral`.
> No fue posible ejecutar el proyecto (compilar, levantar, ni testear)
> porque el equipo no tiene JDK, Maven, Node ni npm instalados. Todo lo que
> aparece como "compilaría" o "fallaría al ejecutar" es inferencia hecha
> leyendo el código, no resultado de un build real.

## 1. Resumen del proyecto

Es un sistema distribuido de tres componentes:

| Capa | Ruta | Stack |
|------|------|-------|
| API de Ventas | `back-Ventas_SpringBoot/Springboot-API-REST` | Spring Boot 3.4.4, JPA, MySQL, Lombok, springdoc-openapi |
| API de Despachos | `back-Despachos_SpringBoot/Springboot-API-REST-DESPACHO` | Spring Boot 3.4.4, JPA, MySQL, Lombok, springdoc-openapi |
| Frontend | `front_despacho` | Vite + React 18, Tailwind, react-hook-form, axios, SweetAlert2 |

La arquitectura es coherente: dos microservicios Spring Boot separados
(uno por contexto delimitado: Ventas y Despachos), y un frontend React
que conversa con ambos. El flujo de negocio es "una venta genera un
despacho, el despacho se cierra". El Despacho se monta en el puerto
`:8081` (explícito en `application.properties`) y Ventas en el
`:8080` por defecto.

---

## 2. Capacidades del código

### 2.1 API de Ventas (`/api/v1/ventas`)

- `POST` crea una venta, validando con bean validation
  (`@NotBlank direccionCompra`, `@NotNull fechaCompra`, `@NotNull despachoGenerado`).
- `PUT /{id}` actualiza parcialmente: hace merge campo a campo, dejando
  intactos los nulos.
- `GET` lista todas las ventas.
- `GET /{id}` obtiene una venta por id.
- `DELETE /{id}` elimina por id.
- `VentaNotFoundException` se mapea a `404` con cuerpo
  `{ status, message }` vía `@ControllerAdvice`.
- Swagger UI en `/swagger-ui.html`, OpenAPI doc en `/v3/api-docs`.
- Hay un test unitario de servicio (`VentaServiceTest`) con Mockito,
  más el test de contexto estándar de Spring Boot.

### 2.2 API de Despachos (`/api/v1/despachos`, puerto 8081)

- `POST` crea un despacho (sin `@Valid`; ver §4.7).
- `PUT /{id}` actualiza reemplazando todos los campos.
- `GET` lista todos los despachos.
- `GET /{id}` obtiene un despacho por id.
- `DELETE /{id}` elimina por id.
- `DespachoNotFoundException` se mapea a `404` con cuerpo
  `{ status, message, errors: { idDespacho: "..." } }`.
- Hay además un `handleMethodArgumentNotValid` que devuelve `400` con
  un mapa `campo → mensaje` por cada error de validación.
- `CorsConfig` configura CORS global (`/**`) más
  `@CrossOrigin(origins = "*")` en el controlador (ver §4.13).
- Swagger UI en `/swagger-ui.html`.
- Solo hay un test de contexto, sin tests de servicio.

### 2.3 Frontend (`front_despacho`)

- SPA React 18 sobre Vite, con Tailwind y PostCSS.
- React Router: una sola ruta `/` que monta `CrudAdmin`.
- `CrudAdmin` arma el shell: `Navbar` a la izquierda (Usuarios,
  Productos, Configuración, todos `href="#"`), y a la derecha
  `PruebaCards`, `Reviews` y `Footer`.
- `PruebaCards` muestra dos tarjetas: una abre `TableCompras`, otra
  abre `TableDespachos`.
- `TableCompras`: hace GET de ventas, filtra las que no tienen
  despacho generado, y al apretar "Generar Despacho" abre un `Modal`
  con `FormDespacho`.
- `FormDespacho`: hace PUT a `/api/v1/ventas/{id}` para marcar
  `despachoGenerado: true`, y luego POST a `/api/v1/despachos` con la
  nueva orden. Muestra SweetAlert2 al terminar.
- `TableDespachos`: hace GET de despachos y al apretar "Cerrar
  despacho" abre un `Modal` con `FormCierreDespacho`.
- `FormCierreDespacho`: hace PUT a `/api/v1/despachos/{id}` con los
  campos `intento` y `despachado`.
- `SearchBar`, `Carrusel`: existen pero no se montan en ninguna parte.
- Vite tiene un proxy de dev que reescribe `/api/*` hacia
  `https://qic534o8o0.execute-api.us-east-1.amazonaws.com`, pero los
  componentes hacen `axios` directo a IPs LAN, así que el proxy
  termina siendo código muerto (ver §4.1).

---

## 3. Estado de compilación y ejecución

No pude correr nada: el equipo donde estoy revisando no tiene JDK,
Maven, Node ni npm. Los comandos `java -version`, `mvn -v`, `node -v`
y `npm -v` devuelven todos `CommandNotFoundException`.

Por lo tanto, **ninguna de las afirmaciones de más abajo fue validada
contra un build real**. Son observaciones estáticas que tú deberías
confirmar ejecutando:

- `./mvnw -DskipTests package` en cada módulo Spring Boot (con JDK 17).
- `npm install && npm run build` en `front_despacho` (con Node ≥18).

Si haces eso y te falla algo que aquí marqué como "compilaría" o
viceversa, te agradecería que me lo reportes para corregir este
documento.

---

## 4. Puntos críticos (a corregir antes de usar el sistema)

### 4.1 El frontend no funciona contra ningún backend como viene de fábrica

- En `TableCompras.jsx`, `TableDespachos.jsx`, `FormDespacho.jsx` y
  `FormCierreDespacho.jsx` las URLs de axios son hardcodeadas a
  direcciones LAN:
  - `http://192.168.30/api/v1/ventas`
  - `http://192.168.30/api/v1/ventas/{id}`
  - `http://192.168.3.20/api/v1/despachos`
  - `http://192.168.320/api/v1/despachos` ← ojo, `320` parece typo
- El proxy de Vite (`vite.config.js`) apunta a AWS API Gateway, no a
  esas IPs.
- Resultado: en cualquier máquina que no esté en esa subred exacta,
  el navegador tira `ERR_CONNECTION_REFUSED`. Y aunque estés en esa
  subred, `/api/v1/despachos` con host `192.168.320` no resuelve
  jamás.

**Sugerencia**: mueve las URLs a variables de entorno
(`import.meta.env.VITE_API_VENTAS`,
`import.meta.env.VITE_API_DESPACHOS`) o usa el proxy `/api/...`.

### 4.2 Los context-load tests fallarán sin secretos externalizados

- Ambos `application.properties` referencian variables
  `${DB_ENDPOINT}`, `${DB_PORT}`, `${DB_NAME}`, `${DB_USERNAME}` y
  `${DB_PASSWORD}`.
- En `Springboot-API-REST` (Ventas) **sí** existe un
  `application-test.properties` con H2, pero está en
  `src/main/resources`, no en `src/test/resources`, y el test no
  tiene `@ActiveProfiles("test")`.
- En `Springboot-API-REST-DESPACHO` (Despachos) **no hay perfil de
  test** en absoluto. El `SpringbootApiRestDespachoApplicationTests`
  intentará abrir MySQL con credenciales vacías.

**Sugerencia**:
- Mueve `application-test.properties` a `src/test/resources/`.
- Agrega `@ActiveProfiles("test")` (o renómbralo a
  `application.properties` dentro de `src/test/resources`).
- Repite lo mismo en el módulo de Despachos.

### 4.3 Tipografía en el nombre del archivo de configuración OpenAPI de Ventas

- `back-Ventas_SpringBoot/Springboot-API-REST/src/main/java/com/citt/config/OpenApiConfing.java`
- El nombre es `OpenApiConfing` (sin la `i` final). Funciona porque
  es consistente consigo mismo, pero el módulo de Despachos usa
  `OpenApiConfig` (bien escrito). Sugerencia: renombrar para
  uniformar.

### 4.4 `application.properties` del módulo Despachos con nombre incorrecto

- Línea 1 de
  `back-Despachos_SpringBoot/Springboot-API-REST-DESPACHO/src/main/resources/application.properties`:
  `spring.application.name=Springboot-API-REST`.
- Debería ser `Springboot-API-REST-DESPACHO`. Cosmético, pero se ve
  feo en logs y en Actuator.

### 4.5 Inconsistencia de campos `entregado` vs `despachado`

- La entidad `Despacho` declara `private boolean despachado = false;`
  (`back-Despachos_SpringBoot/Springboot-API-REST-DESPACHO/src/main/java/com/citt/persistence/entity/Despacho.java`).
- Pero `TableDespachos.jsx` lee `despacho.entregado` (línea 71).
  Como ese campo no existe en la respuesta, todas las filas van a
  mostrar siempre "Despacho pendiente".
- Además `FormDespacho.jsx` arma `jsonData` con `entregado: false`,
  y `FormCierreDespacho.jsx` envía PUT con
  `{ intento, despachado }`.

**Sugerencia**: unifica el nombre (recomiendo `despachado`, que es el
que está en la entidad y en el `PUT`). Cambia la lectura del
frontend y el `entregado: false` del POST inicial.

### 4.6 `DespachoController.crearDespacho` no aplica `@Valid`

- En `back-Despachos_SpringBoot/Springboot-API-REST-DESPACHO/src/main/java/com/citt/controller/DespachoController.java`,
  el método `crearDespacho` importa `jakarta.validation.Valid` pero
  no lo aplica al `@RequestBody`.
- Además, los bean-validation de `Despacho.java` están comentados
  (`//@NotNull(...)`, `//@NotBlank(...)`), así que hoy no hay
  validación efectiva. Si los descomentas y agregas `@Valid`, va a
  entrar el `handleMethodArgumentNotValid` del `RestResponseEntityExceptionHandler`
  y devolver `400` con el mapa de errores.

### 4.7 `DespachoService` con `throws` duplicado

- Línea 12 de `DespachoService.java`:
  `void deleteDespacho(Long idDespacho) throws DespachoNotFoundException, DespachoNotFoundException;`
- Compila igual, pero es ruido. Quita la duplicación.

### 4.8 `VentaServiceImpl.updateVenta` no puede poner `valorCompra` en 0

- `valorCompra` es `int` (primitivo). El guard
  `if (Objects.nonNull(venta.getValorCompra()))` siempre es
  `true` para un primitivo, y si el cliente envía `0` el
  `Objects.nonNull(0)` también es `true`, así que en realidad
  siempre va a pisar el valor con el del request. Pero el contrato
  implícito de "merge parcial" se rompe: el cliente no tiene cómo
  decir "no tocar este campo". Considera cambiar a `Integer`.

### 4.9 `Location` URI mal armada en `DespachoController.crearDespacho`

- La URI se construye con `despacho.getIdDespacho()` **antes** de
  guardar. En un `POST` el id es `null`, así que la cabecera
  `Location` queda como `/api/v1/despachos/null`. Sugerencia:
  guardar primero y armar `Location` con el id resultante.

### 4.10 Inconsistencia en el manejo de errores de validación

- El módulo Despachos tiene `handleMethodArgumentNotValid` que
  devuelve el shape `ErrorMessage` con `errors` poblado.
- El módulo Ventas hereda el comportamiento por defecto de Spring
  Boot: un `400` con un JSON distinto al de su propio `ErrorMessage`.
- Si quieres uniformidad, agrega un override equivalente en
  `back-Ventas_SpringBoot/Springboot-API-REST/src/main/java/com/citt/exceptions/RestResponseEntityExceptionHandler.java`.

### 4.11 Falta de Dockerfiles

- Hay `.dockerignore` en ambos módulos backend pero **no hay
  Dockerfile** ni `docker-compose.yml`. Para un proyecto cuyo
  nombre es "Intro a DevOps", esto es un faltante importante.
- Tampoco hay workflows de CI (`.github/`, `.gitlab-ci.yml`,
  `Jenkinsfile`).

### 4.12 CORS configurado dos veces y propiedad fantasma

- `spring.web.allow-cors=true` en el `application.properties` de
  Despachos **no es una propiedad real de Spring**. Se ignora.
- Cada controller usa `@CrossOrigin(origins = "*")` y además existe
  `CorsConfig` con un `WebMvcConfigurer` global. Elige uno y deja
  uno solo.

### 4.13 `db.json` huérfano

- Existe `front_despacho/db.json` con un array `Ventas` de muestra,
  pero ni Vite ni axios lo leen. Parece sobrante de un
  `json-server` que nunca se terminó de integrar.
- Sugerencia: intégralo con `json-server` como dependencia dev y un
  script `npm run mock`, o bórralo.

### 4.14 Componentes React muertos / errores de código

- `Carrusel.jsx` no se importa en ningún archivo. Además su primer
  `<img src="">` es una imagen rota.
- `SearchBar.jsx` tampoco se usa.
- En `Modal.jsx` línea 12: `e.stopPropagation;` (sin paréntesis) es
  una expresión sin efecto. Debería ser `e.stopPropagation()`.
- El `Modal` no cierra al hacer click en el overlay; solo cierra
  con la "X". Decide si quieres ese comportamiento y, si sí,
  documenta; si no, agrega `onClick={onClose}` al overlay.
- `CrudAdmin.jsx` está exportado como named export
  (`export const CrudAdmin`) y `AppRoutes.jsx` lo importa con
  `{ CrudAdmin }`. Todo lo de `Layouts/` es default export. Decide
  una convención.

### 4.15 Logos externos en `Reviews.jsx`

- `Reviews.jsx` carga imágenes desde `seeklogo.com` por HTTPS. Está
  bien para una demo con Internet, pero en una red cerrada o sin
  salida el render va a quedar feo. Mejor mover a
  `src/assets/images/`.

---

## 5. Observaciones menores

- Lombok está como `<scope>provided</scope>` en ambos `pom.xml`.
  Cualquier IDE sin el plugin Lombok va a mostrar todo el código en
  rojo. Si vas a compartir el repo con más gente, vale la pena
  documentarlo en el `README.md` raíz (que no existe) o cambiar a
  una versión reciente de Lombok que ya viene preconfigurada.
- `spring.jpa.hibernate.ddl-auto=update` está activo en ambos
  servicios. Sirve para una demo, pero documenta que no es para
  producción. No hay Flyway ni Liquibase.
- No hay instancia central de Axios: cada componente construye su
  propio `axios.get/post/put` con headers repetidos. Un
  `src/api/client.js` con `baseURL` y headers por defecto
  limpiaría el código.
- No hay boundary de errores en React. Una `ErrorBoundary` evitaría
  la pantalla blanca si algo revienta.
- El script `lint` existe en `package.json`, pero no hay script
  `format` ni Prettier configurado.
- `springdoc-openapi-starter-webmvc-ui:2.7.0` es compatible con
  Spring Boot 3.x. Solo confirma que en producción no te interese
  bloquear `/swagger-ui.html` con Spring Security.
- Los tests son muy pocos. Sobre todo en Despachos, donde ni
  siquiera hay tests de servicio.

---

## 6. Conclusión

La arquitectura está bien pensada y el flujo de negocio
(venta → despacho → cierre) es coherente entre backend y frontend.

Pero **hoy el sistema no se puede ejecutar de forma confiable**:

- Ninguno de los dos microservicios Spring Boot arranca sin
  variables de entorno seteadas, y los context-load tests van a
  fallar a menos que muevas el `application-test.properties` a
  `src/test/resources/` y actives el perfil de test.
- El frontend no se puede conectar a ningún backend con la
  configuración actual: las URLs hardcodeadas a la subred LAN
  (incluyendo el typo `192.168.320`) bloquean cualquier intento de
  usarlo fuera de esa red específica, y el proxy de Vite apunta a
  otro host.
- El bug más grave a nivel funcional es el mismatch de nombres
  entre `Despacho.despachado` (entidad) y
  `despacho.entregado` (frontend): todas las filas van a aparecer
  como "Despacho pendiente" para siempre.

Si me confirmas que quieres, te puedo dejar los arreglos listos:
unificación del nombre de campo, normalización de las URLs del
frontend vía variables de entorno, y el wiring del perfil de test
en ambos módulos Spring Boot.