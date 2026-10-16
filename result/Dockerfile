
# Build stage
FROM node:22-slim AS builder

WORKDIR /usr/local/app

COPY package*.json ./

RUN npm ci --omit=dev && \
    npm cache clean --force

COPY . .

# Runtime stage: minimal Node.js image without npm
FROM gcr.io/distroless/nodejs22-debian13:nonroot AS runtime

WORKDIR /usr/local/app

COPY --from=builder --chown=nonroot:nonroot /usr/local/app /usr/local/app
COPY --from=builder --chown=nonroot:nonroot /usr/local/app/node_modules /node_modules

ENV PORT=80
EXPOSE 80

CMD ["server.js"]