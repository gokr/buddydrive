FROM nimlang/nim:2.2.0-alpine AS builder

WORKDIR /app

COPY src/ ./src/
RUN nim c -d:release -o:/app/buddydrive-relay src/relay.nim

FROM alpine:3.20

WORKDIR /app

COPY --from=builder /app/buddydrive-relay /app/buddydrive-relay

ENV BUDDYDRIVE_TOKENS=""
ENV BUDDYDRIVE_PORT=41722

EXPOSE 41722

USER nobody

ENTRYPOINT ["/app/buddydrive-relay"]
CMD ["41722"]
