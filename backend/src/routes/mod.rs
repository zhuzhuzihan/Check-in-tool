mod api;
mod health;

use std::{net::IpAddr, net::SocketAddr, time::Duration};

use anyhow::{Context, Result};
use axum::{
    Router,
    extract::{ConnectInfo, FromRequestParts, Request, State},
    http::{
        Extensions, HeaderMap, HeaderName, HeaderValue, Method,
        header::{ACCEPT, AUTHORIZATION, CONTENT_TYPE},
        request::Parts,
    },
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use tower_http::{
    cors::{AllowOrigin, CorsLayer},
    limit::RequestBodyLimitLayer,
    trace::TraceLayer,
};

use crate::{
    error::{AppError, method_not_allowed, route_not_found},
    state::AppState,
};

pub fn build(state: AppState) -> Result<Router> {
    let mut api_router = Router::new()
        .route("/time", get(api::server_time))
        .route("/dashboard", get(api::dashboard))
        .route("/attendance/clock", post(api::clock))
        .route("/devices/trust", post(api::trust_device));
    if state.config.allow_dev_auth {
        api_router = api_router.route("/auth/dev-token", post(api::dev_token));
    }
    api_router = api_router.route_layer(middleware::from_fn_with_state(
        state.clone(),
        rate_limit_requests,
    ));

    let origins = state
        .config
        .cors_allowed_origins
        .iter()
        .map(|origin| {
            HeaderValue::from_str(origin)
                .with_context(|| format!("invalid CORS_ALLOWED_ORIGIN value: {origin}"))
        })
        .collect::<Result<Vec<_>>>()?;
    let cors = CorsLayer::new()
        .allow_origin(AllowOrigin::list(origins))
        .allow_methods([Method::GET, Method::POST])
        .allow_headers([
            ACCEPT,
            AUTHORIZATION,
            CONTENT_TYPE,
            HeaderName::from_static("x-device-enrollment-token"),
            HeaderName::from_static("x-device-fingerprint"),
            HeaderName::from_static("x-dev-auth-secret"),
        ]);

    let body_limit = state.config.request_body_limit_bytes;
    Ok(Router::new()
        .route("/health/live", get(health::live))
        .route("/health/ready", get(health::ready))
        .nest("/api/v1", api_router)
        .fallback(route_not_found)
        .method_not_allowed_fallback(method_not_allowed)
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .layer(RequestBodyLimitLayer::new(body_limit))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            enforce_request_timeout,
        ))
        .with_state(state))
}

#[derive(Debug, Clone, Copy)]
pub struct ClientIp(pub IpAddr);

impl FromRequestParts<AppState> for ClientIp {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        resolve_client_ip(
            &parts.headers,
            &parts.extensions,
            state.config.trust_proxy_headers,
        )
        .map(Self)
    }
}

fn resolve_client_ip(
    headers: &HeaderMap,
    extensions: &Extensions,
    trust_proxy_headers: bool,
) -> Result<IpAddr, AppError> {
    if trust_proxy_headers && let Some(value) = headers.get("x-forwarded-for") {
        let value = value.to_str().map_err(|_| {
            AppError::bad_request(
                "invalid_forwarded_for",
                "X-Forwarded-For is not a valid header value",
            )
        })?;
        let first = value.split(',').next().unwrap_or_default().trim();
        return first.parse::<IpAddr>().map_err(|_| {
            AppError::bad_request(
                "invalid_forwarded_for",
                "The first X-Forwarded-For entry must be an IP address",
            )
        });
    }

    extensions
        .get::<ConnectInfo<SocketAddr>>()
        .map(|ConnectInfo(address)| address.ip())
        .ok_or_else(|| {
            AppError::service_unavailable(
                "client_address_unavailable",
                "The client network address is unavailable",
            )
        })
}

async fn rate_limit_requests(
    State(state): State<AppState>,
    request: Request,
    next: Next,
) -> Response {
    let ip = match resolve_client_ip(
        request.headers(),
        request.extensions(),
        state.config.trust_proxy_headers,
    ) {
        Ok(ip) => ip,
        Err(error) => return error.into_response(),
    };
    match state.redis.rate_limit(ip).await {
        Ok(count) if count > state.config.rate_limit_per_minute => {
            return AppError::too_many_requests(
                "rate_limit_exceeded",
                "Too many requests; retry after the current minute window",
            )
            .into_response();
        }
        Ok(_) => {}
        Err(error) if state.config.redis_fail_closed => {
            tracing::error!(%error, %ip, "Redis rate limiter failed closed");
            return AppError::service_unavailable(
                "rate_limiter_unavailable",
                "The request risk service is unavailable",
            )
            .into_response();
        }
        Err(error) => {
            tracing::warn!(%error, %ip, "Redis rate limiter failed open");
        }
    }
    next.run(request).await
}

async fn enforce_request_timeout(
    State(state): State<AppState>,
    request: Request,
    next: Next,
) -> Response {
    let timeout = Duration::from_secs(state.config.request_timeout_seconds);
    match tokio::time::timeout(timeout, next.run(request)).await {
        Ok(response) => response,
        Err(_) => AppError::service_unavailable(
            "request_timeout",
            "The request exceeded the server time limit",
        )
        .into_response(),
    }
}
