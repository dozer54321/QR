FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund
COPY . .
ARG LATENT_VERSION=dev
ENV LATENT_VERSION=$LATENT_VERSION
ENV NITRO_PRESET=node-server
RUN npm run build:vps && test -d .output

FROM node:22-bookworm-slim
WORKDIR /app
ARG LATENT_VERSION=dev
ENV LATENT_VERSION=$LATENT_VERSION
ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000

COPY --from=build /app/.output ./.output
COPY VERSION ./VERSION

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

LABEL org.opencontainers.image.title="Latent" \
  org.opencontainers.image.description="QR codes, including ones woven into a photograph"

CMD ["node", ".output/server/index.mjs"]
