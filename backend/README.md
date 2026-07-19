# Check-in backend

Axum API backed by PostgreSQL and Redis. PostgreSQL is the source of truth; Redis is used only for per-IP rate limiting and a post-commit state mirror.

## Run

1. Create PostgreSQL and Redis services outside this repository.
2. Copy the values from `.env.example` into a local `.env` and replace every secret.
3. Run `CARGO_BUILD_JOBS=1 cargo run` from `backend/`.

Migrations run automatically at startup. The server binds to `127.0.0.1:8080` by default.

## Local development token

Development token issuance is absent from the router unless `ALLOW_DEV_AUTH=true`. With that setting enabled, `POST /api/v1/auth/dev-token` requires the configured secret:

```sh
curl -X POST \
  -H 'x-dev-auth-secret: your-development-secret' \
  http://127.0.0.1:8080/api/v1/auth/dev-token
```

The endpoint upserts the configured demo user and returns an HS256 bearer token. Keep this endpoint disabled outside local development.

## Device enrollment

`POST /api/v1/devices/trust` requires both a bearer token and `x-device-enrollment-token`. Enrollment and development secrets are compared by hashing both values and then performing a constant-time digest comparison.

## Proxy and risk boundaries

`X-Forwarded-For` is ignored unless `TRUST_PROXY_HEADERS=true`. Enable it only behind a trusted reverse proxy that removes incoming forwarding headers and writes its own. Otherwise a caller can spoof the audit IP and rate-limit identity.

The service records the validated network address as PostgreSQL `inet`, but does not infer location or claim geographic-jump detection. GeoIP/ASN data is probabilistic and needs a separately maintained database, proxy/VPN policy, confidence thresholds, and an appeal path; that risk engine is deliberately left as a later integration boundary.

When Redis is unavailable, `REDIS_FAIL_CLOSED=true` rejects rate-limited API traffic and marks readiness unavailable. In fail-open mode traffic continues, readiness reports a degraded state, and each operation retries the Redis connection. A cache refresh failure after a committed attendance transaction is logged and never changes the successful database result.
