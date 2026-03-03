FROM node:20-alpine

WORKDIR /app

# Install deps first (Docker layer cache)
COPY package*.json ./
RUN npm ci --omit=dev

COPY src/ ./src/

EXPOSE 3001
CMD ["node", "src/index.js"]
