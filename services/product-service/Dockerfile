FROM node:22-alpine AS base
ENV PORT=3000
WORKDIR /app
COPY package.json package-lock.json ./

FROM base AS deps
RUN npm ci --omit=dev

FROM base AS dev
ENV NODE_ENV=development \
    APP_ENV=development
RUN npm ci
COPY . .
RUN chown -R node:node /app
USER node
EXPOSE 3000
CMD ["npm", "run", "dev"]


FROM node:22-alpine AS runtime
ENV NODE_ENV=production \
    APP_ENV=production \
    PORT=3000
WORKDIR /app
RUN apk add --no-cache tini
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src

USER node

EXPOSE 3000

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["npm", "run", "start:production"]
