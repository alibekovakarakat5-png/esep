FROM node:20-alpine

# Свежие CA-сертификаты — нужно для скрапинга adilet.zan.kz и других KZ-сайтов,
# у которых корневой сертификат не входит в minimal alpine bundle.
RUN apk add --no-cache ca-certificates && update-ca-certificates

WORKDIR /app

# Install deps first (Docker layer cache)
COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund

COPY src/ ./src/
COPY scripts/migrate_bot_foundation.js ./scripts/migrate_bot_foundation.js
COPY scripts/migrate_marketing_content.js ./scripts/migrate_marketing_content.js

EXPOSE 3001
CMD ["node", "src/index.js"]
