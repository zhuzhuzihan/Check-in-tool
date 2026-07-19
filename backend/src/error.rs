use std::fmt::Display;

use axum::{
    Json,
    extract::rejection::JsonRejection,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde::Serialize;

use crate::risk::RuleViolation;

#[derive(Debug)]
pub struct AppError {
    status: StatusCode,
    code: &'static str,
    message: String,
}

impl AppError {
    pub fn bad_request(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, code, message)
    }

    pub fn unauthorized(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::UNAUTHORIZED, code, message)
    }

    pub fn forbidden(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::FORBIDDEN, code, message)
    }

    pub fn not_found(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::NOT_FOUND, code, message)
    }

    pub fn conflict(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::CONFLICT, code, message)
    }

    pub fn too_many_requests(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::TOO_MANY_REQUESTS, code, message)
    }

    pub fn service_unavailable(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::SERVICE_UNAVAILABLE, code, message)
    }

    pub fn internal(context: &'static str, error: impl Display) -> Self {
        tracing::error!(context, error = %error, "internal request failure");
        Self::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "internal_error",
            "The server could not complete the request",
        )
    }

    fn new(status: StatusCode, code: &'static str, message: impl Into<String>) -> Self {
        Self {
            status,
            code,
            message: message.into(),
        }
    }
}

impl From<RuleViolation> for AppError {
    fn from(value: RuleViolation) -> Self {
        Self::bad_request(value.code, value.message)
    }
}

impl From<JsonRejection> for AppError {
    fn from(value: JsonRejection) -> Self {
        if value.status() == StatusCode::PAYLOAD_TOO_LARGE {
            Self::bad_request("payload_too_large", "The request body is too large")
        } else {
            Self::bad_request("invalid_json", "The request body is not valid JSON")
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let body = ErrorEnvelope {
            error: ErrorDetail {
                code: self.code,
                message: self.message,
            },
        };
        (self.status, Json(body)).into_response()
    }
}

#[derive(Serialize)]
struct ErrorEnvelope {
    error: ErrorDetail,
}

#[derive(Serialize)]
struct ErrorDetail {
    code: &'static str,
    message: String,
}

pub async fn route_not_found() -> AppError {
    AppError::not_found("route_not_found", "The requested route does not exist")
}

pub async fn method_not_allowed() -> AppError {
    AppError::new(
        StatusCode::METHOD_NOT_ALLOWED,
        "method_not_allowed",
        "The HTTP method is not allowed for this route",
    )
}
