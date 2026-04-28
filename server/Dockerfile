FROM node:20-alpine

# Свежие CA-сертификаты — нужно для скрапинга adilet.zan.kz и других KZ-сайтов,
# у которых корневой сертификат не входит в minimal alpine bundle.
RUN apk add --no-cache ca-certificates && update-ca-certificates

WORKDIR /app

# Install deps first (Docker layer cache)
COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund

COPY src/ ./src/

EXPOSE 3001
CMD ["node", "src/index.js"]
