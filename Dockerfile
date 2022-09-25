FROM ghcr.io/gleam-lang/gleam:v0.23.0-erlang-alpine as BUILDER
WORKDIR /app

ADD gleam.toml .
ADD manifest.toml .
RUN gleam deps download
ADD src src
RUN gleam export erlang-shipment

FROM ghcr.io/gleam-lang/gleam:v0.23.0-erlang-alpine as RUNTIME
WORKDIR /app

COPY --from=BUILDER /app/build/erlang-shipment .

VOLUME /app/data
EXPOSE 3002

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
