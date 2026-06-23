# 网页版镜像：两阶段构建
# 阶段 1：构建 Vue 静态文件
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
# 构建时注入后端 API 地址（生产用相对路径 /api，由 Caddy 反代）
ENV VITE_API_BASE=/api/v1
RUN npm run build

# 阶段 2：nginx 托管静态文件
FROM nginx:alpine
# 删除默认配置，用我们自己的
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
# 拷贝构建产物到 nginx 静态目录
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
