FROM node:22-alpine AS base
ENV PORT=8080
WORKDIR /app
COPY package.json package-lock.json ./

FROM base AS prod-deps
RUN npm ci --omit=dev

FROM base AS dev
ENV NODE_ENV=development
RUN npm ci
COPY . .
RUN chown -R node:node /app
USER node
EXPOSE 8080
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]

FROM base AS build
ENV NODE_ENV=development
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-alpine AS runtime
ENV NODE_ENV=production \
    PORT=8080
WORKDIR /app
RUN apk add --no-cache tini
COPY --from=prod-deps --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --chown=node:node server.cjs package.json ./

USER node

EXPOSE 8080

ENTRYPOINT ["/sbin/tini", "--"]

CMD ["node", "server.cjs"]
