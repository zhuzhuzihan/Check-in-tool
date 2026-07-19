use std::collections::HashSet;

use axum::{
    extract::FromRequestParts,
    http::{header::AUTHORIZATION, request::Parts},
};
use chrono::{DateTime, Duration, Utc};
use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation, decode, encode};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

use crate::{error::AppError, state::AppState};

#[derive(Clone)]
pub struct JwtService {
    secret: Vec<u8>,
}

impl JwtService {
    pub fn new(secret: &[u8]) -> Self {
        Self {
            secret: secret.to_vec(),
        }
    }

    pub fn issue(
        &self,
        user_id: i64,
        ttl: Duration,
    ) -> Result<IssuedToken, jsonwebtoken::errors::Error> {
        let issued_at = Utc::now();
        let expires_at = issued_at + ttl;
        let claims = Claims {
            sub: user_id,
            iat: issued_at.timestamp() as usize,
            exp: expires_at.timestamp() as usize,
        };
        let token = encode(
            &Header::new(Algorithm::HS256),
            &claims,
            &EncodingKey::from_secret(&self.secret),
        )?;
        Ok(IssuedToken { token, expires_at })
    }

    fn verify(&self, token: &str) -> Result<Claims, jsonwebtoken::errors::Error> {
        let mut validation = Validation::new(Algorithm::HS256);
        validation.leeway = 0;
        // jsonwebtoken treats registered `sub` as a string. Our API contract uses a
        // numeric i64 subject, which serde requires through the strongly typed Claims.
        validation.required_spec_claims = HashSet::from(["exp".to_owned()]);
        let token = decode::<Claims>(token, &DecodingKey::from_secret(&self.secret), &validation)?;
        Ok(token.claims)
    }
}

pub struct IssuedToken {
    pub token: String,
    pub expires_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Claims {
    sub: i64,
    iat: usize,
    exp: usize,
}

#[derive(Debug, Clone, Copy)]
pub struct AuthUser {
    pub user_id: i64,
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let value = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|value| value.to_str().ok())
            .ok_or_else(|| {
                AppError::unauthorized("missing_bearer_token", "A bearer token is required")
            })?;
        let token = value.strip_prefix("Bearer ").ok_or_else(|| {
            AppError::unauthorized("invalid_bearer_token", "The bearer token is invalid")
        })?;
        if token.is_empty() {
            return Err(AppError::unauthorized(
                "invalid_bearer_token",
                "The bearer token is invalid",
            ));
        }
        let claims = state.jwt.verify(token).map_err(|error| {
            tracing::debug!(%error, "JWT validation failed");
            AppError::unauthorized("invalid_bearer_token", "The bearer token is invalid")
        })?;
        if claims.sub <= 0 {
            return Err(AppError::unauthorized(
                "invalid_bearer_token",
                "The bearer token is invalid",
            ));
        }
        Ok(Self {
            user_id: claims.sub,
        })
    }
}

pub fn constant_time_secret_eq(provided: &str, expected: &str) -> bool {
    let provided = Sha256::digest(provided.as_bytes());
    let expected = Sha256::digest(expected.as_bytes());
    bool::from(provided.ct_eq(&expected))
}

#[cfg(test)]
mod tests {
    use chrono::Duration;

    use super::{JwtService, constant_time_secret_eq};

    #[test]
    fn jwt_hs256_round_trip_preserves_numeric_subject() {
        let service = JwtService::new(b"a-test-secret-that-is-longer-than-32-bytes");
        let issued = service
            .issue(42, Duration::minutes(5))
            .expect("token issuance");
        let claims = service.verify(&issued.token).expect("token verification");
        assert_eq!(claims.sub, 42);
    }

    #[test]
    fn expired_jwt_is_rejected() {
        let service = JwtService::new(b"a-test-secret-that-is-longer-than-32-bytes");
        let issued = service
            .issue(42, Duration::seconds(-2))
            .expect("token issuance");
        assert!(service.verify(&issued.token).is_err());
    }

    #[test]
    fn secret_comparison_matches_only_equal_values() {
        assert!(constant_time_secret_eq("correct", "correct"));
        assert!(!constant_time_secret_eq("wrong", "correct"));
    }
}
