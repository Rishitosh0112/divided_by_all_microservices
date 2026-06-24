FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
COPY prisma ./prisma

RUN npm install
RUN npx prisma generate

COPY . .

RUN npm run build

EXPOSE 4002

CMD ["sh", "-c", "npx prisma migrate deploy && node dist/index.js"]