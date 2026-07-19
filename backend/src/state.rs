use std::sync::Arc;

use redis::{Client, RedisError, aio::ConnectionManager};
use sqlx::PgPool;
use tokio::sync::RwLock;

use crate::{auth::JwtService, config::Config};

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub redis: RedisStore,
    pub config: Arc<Config>,
    pub jwt: JwtService,
}

impl AppState {
    pub fn new(db: PgPool, redis: RedisStore, config: Config) -> Self {
        let jwt = JwtService::new(config.jwt_secret.as_bytes());
        Self {
            db,
            redis,
            config: Arc::new(config),
            jwt,
        }
    }
}

#[derive(Clone)]
pub struct RedisStore {
    client: Client,
    connection: Arc<RwLock<Option<ConnectionManager>>>,
}

impl RedisStore {
    pub fn new(url: &str) -> Result<Self, RedisError> {
        Ok(Self {
            client: Client::open(url)?,
            connection: Arc::new(RwLock::new(None)),
        })
    }

    async fn connection(&self) -> Result<ConnectionManager, RedisError> {
        if let Some(connection) = self.connection.read().await.as_ref() {
            return Ok(connection.clone());
        }

        let mut slot = self.connection.write().await;
        if let Some(connection) = slot.as_ref() {
            return Ok(connection.clone());
        }
        let connection = self.client.get_connection_manager().await?;
        *slot = Some(connection.clone());
        Ok(connection)
    }

    async fn invalidate(&self) {
        *self.connection.write().await = None;
    }

    pub async fn ping(&self) -> Result<(), RedisError> {
        let mut connection = self.connection().await?;
        let result: Result<String, RedisError> =
            redis::cmd("PING").query_async(&mut connection).await;
        match result {
            Ok(response) if response == "PONG" => Ok(()),
            Ok(response) => Err(RedisError::from((
                redis::ErrorKind::ResponseError,
                "unexpected Redis PING response",
                response,
            ))),
            Err(error) => {
                self.invalidate().await;
                Err(error)
            }
        }
    }

    pub async fn rate_limit(&self, ip: std::net::IpAddr) -> Result<i64, RedisError> {
        const SCRIPT: &str = r#"
            local current = redis.call('INCR', KEYS[1])
            if current == 1 then
                redis.call('EXPIRE', KEYS[1], ARGV[1])
            end
            return current
        "#;

        let mut connection = self.connection().await?;
        let key = format!("ip:{ip}:rate_limit");
        let result = redis::Script::new(SCRIPT)
            .key(key)
            .arg(60_i64)
            .invoke_async(&mut connection)
            .await;
        if result.is_err() {
            self.invalidate().await;
        }
        result
    }

    pub async fn set_attendance_state(&self, user_id: i64, value: &str) -> Result<(), RedisError> {
        let mut connection = self.connection().await?;
        let key = format!("user:{user_id}:state");
        let result = redis::cmd("SET")
            .arg(key)
            .arg(value)
            .query_async(&mut connection)
            .await;
        if result.is_err() {
            self.invalidate().await;
        }
        result
    }
}
