use axum::{Json, extract::State};

use crate::{
    error::AppError,
    models::{Data, HealthStatus, ReadinessStatus},
    state::AppState,
};

pub async fn live() -> Json<Data<HealthStatus>> {
    Json(Data::new(HealthStatus { status: "ok" }))
}

pub async fn ready(State(state): State<AppState>) -> Result<Json<Data<ReadinessStatus>>, AppError> {
    if let Err(error) = sqlx::query_scalar::<_, i32>("SELECT 1")
        .fetch_one(&state.db)
        .await
    {
        tracing::error!(%error, "PostgreSQL readiness check failed");
        return Err(AppError::service_unavailable(
            "postgres_unavailable",
            "PostgreSQL is unavailable",
        ));
    }

    match state.redis.ping().await {
        Ok(()) => Ok(Json(Data::new(ReadinessStatus {
            status: "ready",
            postgres: "ok",
            redis: "ok",
        }))),
        Err(error) if state.config.redis_fail_closed => {
            tracing::error!(%error, "Redis readiness check failed");
            Err(AppError::service_unavailable(
                "redis_unavailable",
                "Redis is unavailable",
            ))
        }
        Err(error) => {
            tracing::warn!(%error, "Redis readiness check is degraded");
            Ok(Json(Data::new(ReadinessStatus {
                status: "degraded",
                postgres: "ok",
                redis: "unavailable",
            })))
        }
    }
}
