# Build context: repository root, including the OCR schemas in docs/ai.
FROM node:24-bookworm-slim AS build
WORKDIR /app/apps/api
COPY apps/api/package.json apps/api/package-lock.json ./
RUN npm ci
COPY apps/api/tsconfig.json ./
COPY apps/api/src ./src
RUN npm run build && npm prune --omit=dev

FROM node:24-bookworm-slim
ENV NODE_ENV=production API_HOST=0.0.0.0 API_PORT=3000
WORKDIR /app/apps/api
COPY --from=build /app/apps/api/node_modules ./node_modules
COPY --from=build /app/apps/api/dist ./dist
COPY apps/api/migrations ./migrations
COPY docs/ai/schemas /app/docs/ai/schemas
USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
