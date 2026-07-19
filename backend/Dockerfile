FROM rust:1.97-slim-bookworm AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY migrations ./migrations
RUN CARGO_BUILD_JOBS=1 cargo build --locked --release

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 app

COPY --from=builder /app/target/release/check-in-backend /usr/local/bin/check-in-backend

USER app
EXPOSE 8080
ENTRYPOINT ["check-in-backend"]
