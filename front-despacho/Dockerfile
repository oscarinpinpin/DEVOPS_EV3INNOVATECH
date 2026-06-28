# ===== Etapa 1: build del SPA con Node =====
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
# Vite compila a /app/dist
RUN npm run build

# ===== Etapa 2: servir estaticos + proxy a los backends con nginx =====
FROM nginx:1.27-alpine
# Reemplazamos la config por defecto por la nuestra (sirve SPA + proxy /api)
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
