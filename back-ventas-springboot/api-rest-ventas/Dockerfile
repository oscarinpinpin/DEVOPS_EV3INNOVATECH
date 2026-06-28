# ===== Etapa 1: build con Maven + JDK 17 =====
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
# Copiamos primero el pom para cachear dependencias
COPY pom.xml .
RUN mvn -q -DskipTests dependency:go-offline || true
# Copiamos el codigo y empaquetamos (sin correr tests, ver nota en la guia)
COPY src ./src
RUN mvn -q -DskipTests clean package

# ===== Etapa 2: runtime liviano solo con el JRE =====
FROM eclipse-temurin:17-jre
WORKDIR /app
# El plugin de Spring Boot genera UN jar ejecutable; el *.jar.original se ignora
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
