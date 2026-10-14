# Stage 1: Build static Go binary
FROM golang:1.24-alpine AS builder

WORKDIR /build

RUN apk add --no-cache ca-certificates tzdata

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w -extldflags '-static'" \
    -o /app/server ./cmd/server/main.go

# Stage 2: Minimal runtime image
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata curl

RUN mkdir -p /data && chmod 777 /data

WORKDIR /

COPY --from=builder /app/server /usr/local/bin/server

ENV PORT=8080
ENV DB_PATH=/data/pair.db

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/healthz || exit 1

CMD ["/usr/local/bin/server"]
