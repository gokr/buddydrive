FROM nimlang/nim:2.2.0-alpine AS builder

RUN apk add --no-cache mariadb-connector-c-dev git

WORKDIR /app

COPY relay.nimble ./
RUN nimble install -y --depsOnly

COPY src/ ./src/
RUN nim c -d:release -d:withKvStore --threads:on --mm:arc -o:/app/buddydrive-relay src/relay.nim

FROM alpine:3.20

RUN apk add --no-cache mariadb-connector-c

RUN ln -s /usr/lib/libmariadb.so.3 /usr/lib/libmariadbclient.so || true
RUN ln -s /usr/lib/libmariadb.so.3 /usr/lib/libmysqlclient.so || true

WORKDIR /app

COPY --from=builder /app/buddydrive-relay /app/buddydrive-relay

ENV BUDDYDRIVE_TOKENS=""
ENV BUDDYDRIVE_PORT=41722
ENV TIDB_CONNECTION_STRING=""

EXPOSE 41722 8080

USER nobody

ENTRYPOINT ["/app/buddydrive-relay"]
CMD ["41722", "8080"]
