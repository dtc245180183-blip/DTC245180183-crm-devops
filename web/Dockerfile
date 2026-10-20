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

# Tạo người dùng và nhóm không đặc quyền appuser (UID/GID 1001)
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

COPY --from=build --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --chown=appuser:appgroup . .

# Tạo thư mục uploads với quyền ghi cho appuser
RUN mkdir -p /app/uploads && chown -R appuser:appgroup /app/uploads

# Chuyển sang người dùng không đặc quyền
USER appuser

EXPOSE 3000
CMD ["node", "src/server.js"]
