# Amigo激活服务（零依赖，Node 自带模块）
FROM node:20-alpine
WORKDIR /app
COPY server.js admin.js ./
ENV PORT=8787
ENV LICENSE_DB=/data/licenses.json
EXPOSE 8787
VOLUME ["/data"]
CMD ["node", "server.js"]
