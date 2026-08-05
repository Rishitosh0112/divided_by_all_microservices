FROM node:22-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY nest-cli.json tsconfig.json ./
COPY prisma ./prisma
RUN npx prisma generate

COPY src ./src
RUN npm run build

EXPOSE 4003

CMD ["node", "dist/main.js"]
