# Multi-stage build for CRM Web App
# Stage 1: Build & Dependencies
FROM node:20.18.3-alpine AS build
WORKDIR /app
RUN apk add --no-cache python3 make g++
COPY package*.json ./
RUN npm install --omit=dev

# Stage 2: Production Runtime
FROM node:20.18.3-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY . .
RUN mkdir -p /app/uploads
EXPOSE 3000
CMD ["node", "src/server.js"]
