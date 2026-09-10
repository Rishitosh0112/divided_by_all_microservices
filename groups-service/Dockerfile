FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
COPY prisma ./prisma

RUN npm ci
RUN npx prisma generate

COPY . .

RUN npm run build

EXPOSE 4002

# Schema changes run in the dedicated migration task/job before API tasks deploy.
# API containers must only serve Group Service traffic.
CMD ["node", "dist/index.js"]
