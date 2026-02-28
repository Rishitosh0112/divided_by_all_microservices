# Use Node LTS
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package files first (for caching)
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy rest of code
COPY . .

# Generate Prisma client
RUN npx prisma generate

# Expose port
EXPOSE 4002

# Start app
CMD ["npm", "run", "dev"]