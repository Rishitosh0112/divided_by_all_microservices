# 1. Base image (Node.js runtime)
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./

RUN npm ci

COPY . .

RUN npm run build

# Amazon DocumentDB requires TLS. Download AWS's public RDS/DocumentDB CA
# bundle into the image so the Mongoose driver can verify the database server
# certificate. The production MONGO_URL will point tlsCAFile at this path.
# No database password or connection URL is baked into the image.
RUN apk add --no-cache curl \
  && curl --fail --silent --show-error --location \
    https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
    --output /app/global-bundle.pem \
  && chmod 0644 /app/global-bundle.pem

EXPOSE 8000

CMD ["npm", "start"]


