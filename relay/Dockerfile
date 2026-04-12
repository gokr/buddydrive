FROM nimlang/nim:2.2.8-alpine AS builder

RUN apk add --no-cache mariadb-connector-c-dev git

WORKDIR /app

COPY relay.nimble ./
RUN nimble install -y --depsOnly

COPY src/ ./src/
RUN nim c -d:release -d:withKvStore --threads:on --mm:arc -o:/app/buddydrive-relay src/relay.nim

FROM ubuntu:24.04

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libmysqlclient21 ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/buddydrive-relay /app/buddydrive-relay

ENV BUDDYDRIVE_TOKENS=""
ENV BUDDYDRIVE_PORT=41722
ENV TIDB_CONNECTION_STRING=""

EXPOSE 41722 8080

USER nobody

ENTRYPOINT ["/app/buddydrive-relay"]
CMD ["41722", "8080"]
