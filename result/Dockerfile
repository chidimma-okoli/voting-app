
# Build stage
FROM node:22-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392 AS builder

WORKDIR /usr/local/app

COPY package*.json ./

RUN npm ci --omit=dev && \
    npm cache clean --force

COPY . .

# Runtime stage: minimal Node.js image without npm
FROM gcr.io/distroless/nodejs22-debian13:nonroot@sha256:ec2313763dd43931543bd03830466e0c409ce73a487e8d46f10db72d3b816c1c AS runtime

WORKDIR /usr/local/app

COPY --from=builder --chown=nonroot:nonroot /usr/local/app /usr/local/app
COPY --from=builder --chown=nonroot:nonroot /usr/local/app/node_modules /node_modules

ENV PORT=80
EXPOSE 80

CMD ["server.js"]