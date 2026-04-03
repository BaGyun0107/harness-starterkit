# back-* 배포 레포에서 사용하는 Dockerfile
# sync 시 apps/back/ 내용이 레포 루트로 배치되므로 경로는 . 기준
# ---- Builder ----
FROM node:24-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . ./
RUN npx prisma generate
RUN npm run build

# ---- Runner ----
FROM node:24-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/src/generated ./src/generated

EXPOSE 8080

CMD ["node", "--enable-source-maps", "dist/server.js"]
