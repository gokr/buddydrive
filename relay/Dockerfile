FROM ubuntu:24.04 AS builder

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends gcc build-essential libc6-dev \
    ca-certificates curl git xz-utils libssl-dev libmariadb-dev && \
    apt-get clean

RUN curl https://nim-lang.org/choosenim/init.sh -sSf | bash -s -- -y
ENV PATH=/root/.nimble/bin:/root/.choosenim/toolchains/nim-2.2.8/bin:$PATH

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

ENV BUDDYDRIVE_PORT=41722
ENV TIDB_CONNECTION_STRING=""

EXPOSE 41722 8080

USER nobody

ENTRYPOINT ["/app/buddydrive-relay"]
CMD ["41722", "8080"]
