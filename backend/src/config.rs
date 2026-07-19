use std::{env, net::SocketAddr, str::FromStr};

use anyhow::{Context, Result, bail};

#[derive(Clone)]
pub struct Config {
    pub bind_addr: SocketAddr,
    pub database_url: String,
    pub redis_url: String,
    pub jwt_secret: String,
    pub jwt_ttl_seconds: i64,
    pub device_enrollment_token: String,
    pub cors_allowed_origins: Vec<String>,
    pub trust_proxy_headers: bool,
    pub reject_emulators: bool,
    pub redis_fail_closed: bool,
    pub rate_limit_per_minute: i64,
    pub allow_dev_auth: bool,
    pub dev_auth_secret: Option<String>,
    pub dev_user_id: i64,
    pub dev_display_name: String,
    pub dev_token_ttl_seconds: i64,
    pub database_max_connections: u32,
    pub request_body_limit_bytes: usize,
    pub request_timeout_seconds: u64,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        let allow_dev_auth = parse_or("ALLOW_DEV_AUTH", false)?;
        let jwt_secret = required("JWT_SECRET")?;
        let device_enrollment_token = required("DEVICE_ENROLLMENT_TOKEN")?;
        ensure_secret_length("JWT_SECRET", &jwt_secret)?;
        ensure_secret_length("DEVICE_ENROLLMENT_TOKEN", &device_enrollment_token)?;

        let dev_auth_secret = env::var("DEV_AUTH_SECRET")
            .ok()
            .filter(|value| !value.is_empty());
        if allow_dev_auth {
            let secret = dev_auth_secret
                .as_deref()
                .context("DEV_AUTH_SECRET is required when ALLOW_DEV_AUTH=true")?;
            ensure_secret_length("DEV_AUTH_SECRET", secret)?;
        }

        let cors_allowed_origins = env_or(
            "CORS_ALLOWED_ORIGIN",
            "http://localhost:3000,http://127.0.0.1:3000",
        )
        .split(',')
        .map(str::trim)
        .filter(|origin| !origin.is_empty())
        .map(ToOwned::to_owned)
        .collect::<Vec<_>>();
        if cors_allowed_origins.is_empty() {
            bail!("CORS_ALLOWED_ORIGIN must contain at least one origin");
        }

        let config = Self {
            bind_addr: parse_or("BIND_ADDR", SocketAddr::from(([127, 0, 0, 1], 8080)))?,
            database_url: required("DATABASE_URL")?,
            redis_url: required("REDIS_URL")?,
            jwt_secret,
            jwt_ttl_seconds: parse_or("JWT_TTL_SECONDS", 3_600)?,
            device_enrollment_token,
            cors_allowed_origins,
            trust_proxy_headers: parse_or("TRUST_PROXY_HEADERS", false)?,
            reject_emulators: parse_or("REJECT_EMULATORS", true)?,
            redis_fail_closed: parse_or("REDIS_FAIL_CLOSED", true)?,
            rate_limit_per_minute: parse_or("RATE_LIMIT_PER_MINUTE", 60)?,
            allow_dev_auth,
            dev_auth_secret,
            dev_user_id: parse_or("DEV_USER_ID", 1)?,
            dev_display_name: env_or("DEV_DISPLAY_NAME", "Demo User"),
            dev_token_ttl_seconds: parse_or("DEV_TOKEN_TTL_SECONDS", 86_400)?,
            database_max_connections: parse_or("DATABASE_MAX_CONNECTIONS", 5)?,
            request_body_limit_bytes: parse_or("REQUEST_BODY_LIMIT_BYTES", 65_536)?,
            request_timeout_seconds: parse_or("REQUEST_TIMEOUT_SECONDS", 15)?,
        };
        config.validate()?;
        Ok(config)
    }

    fn validate(&self) -> Result<()> {
        if self.jwt_ttl_seconds <= 0 || self.dev_token_ttl_seconds <= 0 {
            bail!("JWT TTL values must be positive");
        }
        if self.rate_limit_per_minute <= 0 {
            bail!("RATE_LIMIT_PER_MINUTE must be positive");
        }
        if self.dev_user_id <= 0 {
            bail!("DEV_USER_ID must be positive");
        }
        if self.dev_display_name.trim().is_empty() || self.dev_display_name.chars().count() > 120 {
            bail!("DEV_DISPLAY_NAME must contain between 1 and 120 characters");
        }
        if self.database_max_connections == 0
            || self.request_body_limit_bytes == 0
            || self.request_timeout_seconds == 0
        {
            bail!("database, body limit, and timeout settings must be positive");
        }
        Ok(())
    }
}

fn required(name: &str) -> Result<String> {
    let value = env::var(name).with_context(|| format!("{name} is required"))?;
    if value.is_empty() {
        bail!("{name} must not be empty");
    }
    Ok(value)
}

fn env_or(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.to_owned())
}

fn parse_or<T>(name: &str, default: T) -> Result<T>
where
    T: FromStr,
    T::Err: std::error::Error + Send + Sync + 'static,
{
    match env::var(name) {
        Ok(value) => value
            .parse::<T>()
            .with_context(|| format!("{name} has an invalid value")),
        Err(env::VarError::NotPresent) => Ok(default),
        Err(error) => Err(error).with_context(|| format!("could not read {name}")),
    }
}

fn ensure_secret_length(name: &str, secret: &str) -> Result<()> {
    if secret.len() < 32 {
        bail!("{name} must be at least 32 bytes");
    }
    Ok(())
}
