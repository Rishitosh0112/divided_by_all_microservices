# 1. Base image (Node.js runtime)
FROM node:20-alpine

# 2. Create app directory inside container
WORKDIR /app

# 3. Copy dependency files
COPY package*.json ./

# 4. Install app dependencies
RUN npm install

# 5. Copy app source code
COPY . .

#Compile TypeScript to JavaScript
RUN npm run build

# 6. Expose port (documentation purpose)
EXPOSE 4000

# 7. Start the app
CMD ["npm", "run", "dev"]




