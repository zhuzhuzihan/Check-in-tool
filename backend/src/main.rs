use std::net::SocketAddr;

use anyhow::{Context, Result, bail};
use check_in_backend::{
    build_router,
    config::Config,
    state::{AppState, RedisStore},
};
use sqlx::postgres::PgPoolOptions;
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("check_in_backend=info,tower_http=info")),
        )
        .try_init()
        .map_err(|error| anyhow::anyhow!("initialize tracing: {error}"))?;

    let config = Config::from_env().context("load configuration")?;
    let bind_addr = config.bind_addr;
    let database = PgPoolOptions::new()
        .max_connections(config.database_max_connections)
        .connect(&config.database_url)
        .await
        .context("connect to PostgreSQL")?;
    sqlx::migrate!("./migrations")
        .run(&database)
        .await
        .context("run PostgreSQL migrations")?;

    let redis = RedisStore::new(&config.redis_url).context("configure Redis client")?;
    if let Err(error) = redis.ping().await {
        if config.redis_fail_closed {
            bail!("connect to Redis: {error}");
        }
        tracing::warn!(%error, "Redis unavailable at startup; continuing in fail-open mode");
    }

    let state = AppState::new(database, redis, config);
    let app = build_router(state).context("build HTTP router")?;
    let listener = TcpListener::bind(bind_addr)
        .await
        .with_context(|| format!("bind HTTP listener to {bind_addr}"))?;
    tracing::info!(%bind_addr, "check-in backend listening");

    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await
    .context("serve HTTP API")?;
    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        if let Err(error) = tokio::signal::ctrl_c().await {
            tracing::error!(%error, "could not install Ctrl+C signal handler");
        }
    };

    #[cfg(unix)]
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                signal.recv().await;
            }
            Err(error) => {
                tracing::error!(%error, "could not install SIGTERM signal handler");
                std::future::pending::<()>().await;
            }
        }
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        () = ctrl_c => {}
        () = terminate => {}
    }
    tracing::info!("shutdown signal received");
}
