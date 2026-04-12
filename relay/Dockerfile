FROM nimlang/nim:2.2.0-alpine AS builder

RUN apk add --no-cache mariadb-connector-c-dev

WORKDIR /app

COPY src/ ./src/
COPY relay.nimble ./
RUN nim c -d:release -d:withKvStore --threads:on --mm:arc -o:/app/buddydrive-relay src/relay.nim

FROM alpine:3.20

RUN apk add --no-cache mariadb-connector-c

WORKDIR /app

COPY --from=builder /app/buddydrive-relay /app/buddydrive-relay

ENV BUDDYDRIVE_TOKENS=""
ENV BUDDYDRIVE_PORT=41722
ENV TIDB_CONNECTION_STRING=""

EXPOSE 41722 8080

USER nobody

ENTRYPOINT ["/app/buddydrive-relay"]
CMD ["41722", "8080"]
