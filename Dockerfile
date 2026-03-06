# ── Stage 1: Build Flutter web ────────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app
COPY pubspec.* ./
RUN flutter pub get --no-example

COPY . .
RUN flutter build web --release --no-tree-shake-icons

# ── Stage 2: Serve with Nginx ─────────────────────────────────────────────────
FROM nginx:1.27-alpine AS runner

# Copy built Flutter web files
COPY --from=builder /app/build/web /usr/share/nginx/html

# Copy Nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
