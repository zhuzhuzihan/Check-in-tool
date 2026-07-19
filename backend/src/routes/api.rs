use std::cmp;

use axum::{
    Json,
    extract::{State, rejection::JsonRejection},
    http::HeaderMap,
};
use chrono::{DateTime, Days, Duration, NaiveDate, Utc};
use ipnetwork::IpNetwork;
use serde::Serialize;
use serde_json::Value;
use sqlx::types::Json as SqlJson;

use super::ClientIp;
use crate::{
    auth::{AuthUser, constant_time_secret_eq},
    error::AppError,
    models::{
        AttendanceAction, AttendanceState, ClockRequest, DailyHours, Dashboard, Data,
        DevTokenResponse, ServerTime, TrustDeviceRequest, TrustDeviceResponse,
    },
    risk::{validate_client_drift, validate_clock_request, validate_device, validate_fingerprint},
    state::AppState,
};

pub async fn server_time() -> Json<Data<ServerTime>> {
    Json(Data::new(ServerTime {
        server_time: Utc::now(),
    }))
}

pub async fn dashboard(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
) -> Result<Json<Data<Dashboard>>, AppError> {
    let fingerprint = optional_fingerprint(&headers)?;
    let dashboard =
        load_dashboard(&state, auth.user_id, fingerprint.as_deref(), Utc::now()).await?;
    Ok(Json(Data::new(dashboard)))
}

pub async fn clock(
    State(state): State<AppState>,
    auth: AuthUser,
    ClientIp(ip): ClientIp,
    payload: Result<Json<ClockRequest>, JsonRejection>,
) -> Result<Json<Data<Dashboard>>, AppError> {
    let Json(request) = payload.map_err(AppError::from)?;
    let validated = validate_clock_request(&request, state.config.reject_emulators)?;
    ensure_user_exists(&state, auth.user_id).await?;

    let mut transaction = state
        .db
        .begin()
        .await
        .map_err(|error| AppError::internal("begin clock transaction", error))?;

    sqlx::query(
        "INSERT INTO attendance_states (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING",
    )
    .bind(auth.user_id)
    .execute(&mut *transaction)
    .await
    .map_err(|error| AppError::internal("ensure attendance state", error))?;

    let current = sqlx::query_as::<_, StateRow>(
        r#"
        SELECT state, active_since, last_action_at
        FROM attendance_states
        WHERE user_id = $1
        FOR UPDATE
        "#,
    )
    .bind(auth.user_id)
    .fetch_one(&mut *transaction)
    .await
    .map_err(|error| AppError::internal("lock attendance state", error))?;

    let existing = sqlx::query_as::<_, ExistingRecord>(
        r#"
        SELECT action, device_fingerprint, device_info, client_time,
               touch_duration_ms, touch_distance_px, touch_sample_count
        FROM attendance_records
        WHERE user_id = $1 AND request_id = $2
        "#,
    )
    .bind(auth.user_id)
    .bind(request.request_id)
    .fetch_optional(&mut *transaction)
    .await
    .map_err(|error| AppError::internal("load idempotent clock record", error))?;

    if let Some(existing) = existing {
        if !existing.matches(&request, &validated.fingerprint, validated.client_time) {
            return Err(AppError::conflict(
                "request_id_conflict",
                "request_id was already used with a different clock request",
            ));
        }
        transaction
            .commit()
            .await
            .map_err(|error| AppError::internal("commit idempotent clock transaction", error))?;
        refresh_state_cache(&state, auth.user_id, &current).await;
        let dashboard = load_dashboard(
            &state,
            auth.user_id,
            Some(&validated.fingerprint),
            Utc::now(),
        )
        .await?;
        return Ok(Json(Data::new(dashboard)));
    }

    let server_time = Utc::now();
    validate_client_drift(validated.client_time, server_time)?;

    let trusted = sqlx::query(
        r#"
        UPDATE trusted_devices
        SET device_info = $3, last_seen_at = $4
        WHERE user_id = $1 AND device_fingerprint = $2 AND revoked_at IS NULL
        "#,
    )
    .bind(auth.user_id)
    .bind(&validated.fingerprint)
    .bind(SqlJson(request.device_info.clone()))
    .bind(server_time)
    .execute(&mut *transaction)
    .await
    .map_err(|error| AppError::internal("verify trusted device", error))?;
    if trusted.rows_affected() == 0 {
        return Err(AppError::forbidden(
            "device_not_trusted",
            "The device must be enrolled before clocking attendance",
        ));
    }

    let next_state = current.state.transition(request.action).ok_or_else(|| {
        AppError::conflict(
            "invalid_state_transition",
            invalid_transition_message(current.state, request.action),
        )
    })?;
    let work_duration_ms = match request.action {
        AttendanceAction::ClockIn => None,
        AttendanceAction::ClockOut => {
            let active_since = current.active_since.ok_or_else(|| {
                AppError::internal(
                    "validate locked attendance state",
                    "working state has no active_since timestamp",
                )
            })?;
            let duration = server_time.signed_duration_since(active_since);
            if duration < Duration::zero() {
                return Err(AppError::internal(
                    "calculate work duration",
                    "active_since is later than server time",
                ));
            }
            Some(duration.num_milliseconds())
        }
    };

    sqlx::query(
        r#"
        INSERT INTO attendance_records (
            user_id, action, state_before, state_after, server_time, client_time,
            ip_address, device_fingerprint, device_info, work_duration,
            touch_duration_ms, touch_distance_px, touch_sample_count, request_id
        ) VALUES (
            $1, $2, $3, $4, $5, $6, $7, $8, $9,
            CASE WHEN $10::BIGINT IS NULL THEN NULL
                 ELSE $10::BIGINT * INTERVAL '1 millisecond' END,
            $11, $12, $13, $14
        )
        "#,
    )
    .bind(auth.user_id)
    .bind(request.action)
    .bind(current.state)
    .bind(next_state)
    .bind(server_time)
    .bind(validated.client_time)
    .bind(IpNetwork::from(ip))
    .bind(&validated.fingerprint)
    .bind(SqlJson(request.device_info.clone()))
    .bind(work_duration_ms)
    .bind(validated.touch_duration_ms)
    .bind(validated.touch_distance_px)
    .bind(validated.touch_sample_count)
    .bind(request.request_id)
    .execute(&mut *transaction)
    .await
    .map_err(|error| AppError::internal("insert attendance record", error))?;

    let active_since = match request.action {
        AttendanceAction::ClockIn => Some(server_time),
        AttendanceAction::ClockOut => None,
    };
    sqlx::query(
        r#"
        UPDATE attendance_states
        SET state = $2, active_since = $3, last_action_at = $4, updated_at = $4
        WHERE user_id = $1
        "#,
    )
    .bind(auth.user_id)
    .bind(next_state)
    .bind(active_since)
    .bind(server_time)
    .execute(&mut *transaction)
    .await
    .map_err(|error| AppError::internal("update attendance state", error))?;

    transaction
        .commit()
        .await
        .map_err(|error| AppError::internal("commit clock transaction", error))?;

    let updated = StateRow {
        state: next_state,
        active_since,
        last_action_at: Some(server_time),
    };
    refresh_state_cache(&state, auth.user_id, &updated).await;
    let dashboard = load_dashboard(
        &state,
        auth.user_id,
        Some(&validated.fingerprint),
        Utc::now(),
    )
    .await?;
    Ok(Json(Data::new(dashboard)))
}

pub async fn trust_device(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    payload: Result<Json<TrustDeviceRequest>, JsonRejection>,
) -> Result<Json<Data<TrustDeviceResponse>>, AppError> {
    let provided = headers
        .get("x-device-enrollment-token")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    if !constant_time_secret_eq(provided, &state.config.device_enrollment_token) {
        return Err(AppError::forbidden(
            "invalid_enrollment_token",
            "The device enrollment token is invalid",
        ));
    }

    let Json(request) = payload.map_err(AppError::from)?;
    let fingerprint = validate_device(
        &request.device_fingerprint,
        &request.device_info,
        state.config.reject_emulators,
    )?;
    ensure_user_exists(&state, auth.user_id).await?;
    let trusted_at = Utc::now();

    let trusted_at = sqlx::query_scalar::<_, DateTime<Utc>>(
        r#"
        INSERT INTO trusted_devices (
            user_id, device_fingerprint, device_info, trusted_at, last_seen_at
        ) VALUES ($1, $2, $3, $4, $4)
        ON CONFLICT (user_id, device_fingerprint) DO UPDATE
        SET device_info = EXCLUDED.device_info,
            trusted_at = EXCLUDED.trusted_at,
            last_seen_at = EXCLUDED.last_seen_at,
            revoked_at = NULL
        RETURNING trusted_at
        "#,
    )
    .bind(auth.user_id)
    .bind(&fingerprint)
    .bind(SqlJson(request.device_info))
    .bind(trusted_at)
    .fetch_one(&state.db)
    .await
    .map_err(|error| AppError::internal("upsert trusted device", error))?;

    Ok(Json(Data::new(TrustDeviceResponse {
        device_fingerprint: fingerprint,
        trusted_at,
        device_trusted: true,
    })))
}

pub async fn dev_token(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Data<DevTokenResponse>>, AppError> {
    let provided = headers
        .get("x-dev-auth-secret")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    let expected = state.config.dev_auth_secret.as_deref().unwrap_or_default();
    if !constant_time_secret_eq(provided, expected) {
        return Err(AppError::forbidden(
            "invalid_dev_auth_secret",
            "The development authentication secret is invalid",
        ));
    }

    sqlx::query(
        r#"
        INSERT INTO users (id, display_name)
        VALUES ($1, $2)
        ON CONFLICT (id) DO UPDATE
        SET display_name = EXCLUDED.display_name, updated_at = now()
        "#,
    )
    .bind(state.config.dev_user_id)
    .bind(state.config.dev_display_name.trim())
    .execute(&state.db)
    .await
    .map_err(|error| AppError::internal("upsert development user", error))?;

    let issued = state
        .jwt
        .issue(
            state.config.dev_user_id,
            Duration::seconds(state.config.dev_token_ttl_seconds),
        )
        .map_err(|error| AppError::internal("issue development JWT", error))?;
    Ok(Json(Data::new(DevTokenResponse {
        token: issued.token,
        token_type: "Bearer",
        expires_at: issued.expires_at,
        user_id: state.config.dev_user_id,
    })))
}

#[derive(sqlx::FromRow)]
struct StateRow {
    state: AttendanceState,
    active_since: Option<DateTime<Utc>>,
    last_action_at: Option<DateTime<Utc>>,
}

#[derive(sqlx::FromRow)]
struct ExistingRecord {
    action: AttendanceAction,
    device_fingerprint: String,
    device_info: SqlJson<Value>,
    client_time: DateTime<Utc>,
    touch_duration_ms: i32,
    touch_distance_px: f64,
    touch_sample_count: i32,
}

impl ExistingRecord {
    fn matches(
        &self,
        request: &ClockRequest,
        fingerprint: &str,
        client_time: DateTime<Utc>,
    ) -> bool {
        self.action == request.action
            && self.device_fingerprint == fingerprint
            && self.device_info.0 == request.device_info
            && self.client_time == client_time
            && i64::from(self.touch_duration_ms) == request.touch_duration_ms
            && self.touch_distance_px == request.touch_distance_px
            && i64::from(self.touch_sample_count) == request.touch_sample_count
    }
}

#[derive(sqlx::FromRow)]
struct DashboardBase {
    display_name: String,
    state: AttendanceState,
    active_since: Option<DateTime<Utc>>,
    last_action_at: Option<DateTime<Utc>>,
}

#[derive(sqlx::FromRow)]
struct CompletedShift {
    server_time: DateTime<Utc>,
    duration_ms: i64,
}

async fn load_dashboard(
    state: &AppState,
    user_id: i64,
    fingerprint: Option<&str>,
    now: DateTime<Utc>,
) -> Result<Dashboard, AppError> {
    let mut transaction = state
        .db
        .begin()
        .await
        .map_err(|error| AppError::internal("begin dashboard transaction", error))?;
    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
        .execute(&mut *transaction)
        .await
        .map_err(|error| AppError::internal("configure dashboard transaction", error))?;

    let base = sqlx::query_as::<_, DashboardBase>(
        r#"
        SELECT u.display_name,
               COALESCE(s.state, 'off_duty'::attendance_status) AS state,
               s.active_since,
               s.last_action_at
        FROM users u
        LEFT JOIN attendance_states s ON s.user_id = u.id
        WHERE u.id = $1
        "#,
    )
    .bind(user_id)
    .fetch_optional(&mut *transaction)
    .await
    .map_err(|error| AppError::internal("load dashboard state", error))?
    .ok_or_else(|| AppError::unauthorized("invalid_bearer_token", "The bearer token is invalid"))?;

    let today_start = now
        .date_naive()
        .and_hms_opt(0, 0, 0)
        .expect("midnight is a valid time")
        .and_utc();
    let first_day_start = today_start - Duration::days(6);
    let completed = sqlx::query_as::<_, CompletedShift>(
        r#"
        SELECT server_time,
               (EXTRACT(EPOCH FROM work_duration) * 1000)::BIGINT AS duration_ms
        FROM attendance_records
        WHERE user_id = $1
          AND action = 'clock_out'
          AND work_duration IS NOT NULL
          AND server_time > $2
        ORDER BY server_time
        "#,
    )
    .bind(user_id)
    .bind(first_day_start)
    .fetch_all(&mut *transaction)
    .await
    .map_err(|error| AppError::internal("load completed shifts", error))?;

    let mut worked_by_day = [0_i64; 7];
    for shift in completed {
        let shift_start = shift
            .server_time
            .checked_sub_signed(Duration::milliseconds(shift.duration_ms))
            .ok_or_else(|| {
                AppError::internal(
                    "calculate dashboard shift",
                    "stored shift duration overflowed",
                )
            })?;
        add_shift_to_days(
            &mut worked_by_day,
            first_day_start,
            shift_start,
            shift.server_time,
        );
    }
    if base.state != AttendanceState::OffDuty {
        let active_since = base.active_since.ok_or_else(|| {
            AppError::internal(
                "calculate active dashboard shift",
                "working state has no active_since timestamp",
            )
        })?;
        if active_since > now {
            return Err(AppError::internal(
                "calculate active dashboard shift",
                "active_since is later than server time",
            ));
        }
        add_shift_to_days(&mut worked_by_day, first_day_start, active_since, now);
    }

    let weekly_hours = worked_by_day
        .into_iter()
        .enumerate()
        .map(|(index, worked_ms)| DailyHours {
            day: (first_day_start + Duration::days(index as i64)).date_naive(),
            worked_ms,
        })
        .collect::<Vec<_>>();
    let today_worked_ms = weekly_hours.last().map_or(0, |day| day.worked_ms);

    let attended_days = sqlx::query_scalar::<_, NaiveDate>(
        r#"
        SELECT DISTINCT (server_time AT TIME ZONE 'UTC')::date AS day
        FROM attendance_records
        WHERE user_id = $1 AND action = 'clock_in' AND server_time <= $2
        ORDER BY day DESC
        "#,
    )
    .bind(user_id)
    .bind(now)
    .fetch_all(&mut *transaction)
    .await
    .map_err(|error| AppError::internal("load attendance streak", error))?;
    let streak_days = calculate_streak(&attended_days, now.date_naive());

    let device_trusted = match fingerprint {
        Some(fingerprint) => sqlx::query_scalar::<_, bool>(
            r#"
            SELECT EXISTS (
                SELECT 1 FROM trusted_devices
                WHERE user_id = $1 AND device_fingerprint = $2 AND revoked_at IS NULL
            )
            "#,
        )
        .bind(user_id)
        .bind(fingerprint)
        .fetch_one(&mut *transaction)
        .await
        .map_err(|error| AppError::internal("load dashboard device trust", error))?,
        None => false,
    };

    let dashboard = Dashboard {
        display_name: base.display_name,
        state: base.state,
        server_time: now,
        today_worked_ms,
        active_since: base.active_since,
        last_action_at: base.last_action_at,
        weekly_hours,
        streak_days,
        device_trusted,
    };
    transaction
        .commit()
        .await
        .map_err(|error| AppError::internal("commit dashboard transaction", error))?;
    Ok(dashboard)
}

fn add_shift_to_days(
    totals: &mut [i64; 7],
    first_day_start: DateTime<Utc>,
    shift_start: DateTime<Utc>,
    shift_end: DateTime<Utc>,
) {
    for (index, total) in totals.iter_mut().enumerate() {
        let day_start = first_day_start + Duration::days(index as i64);
        let day_end = day_start + Duration::days(1);
        let overlap_start = cmp::max(shift_start, day_start);
        let overlap_end = cmp::min(shift_end, day_end);
        if overlap_end > overlap_start {
            *total = total.saturating_add(
                overlap_end
                    .signed_duration_since(overlap_start)
                    .num_milliseconds(),
            );
        }
    }
}

fn calculate_streak(days: &[NaiveDate], today: NaiveDate) -> i64 {
    let Some(&most_recent) = days.first() else {
        return 0;
    };
    let yesterday = today.checked_sub_days(Days::new(1));
    if most_recent != today && Some(most_recent) != yesterday {
        return 0;
    }

    let mut expected = most_recent;
    let mut streak = 0_i64;
    for &day in days {
        if day != expected {
            break;
        }
        streak += 1;
        let Some(previous) = expected.checked_sub_days(Days::new(1)) else {
            break;
        };
        expected = previous;
    }
    streak
}

async fn ensure_user_exists(state: &AppState, user_id: i64) -> Result<(), AppError> {
    let exists = sqlx::query_scalar::<_, bool>("SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)")
        .bind(user_id)
        .fetch_one(&state.db)
        .await
        .map_err(|error| AppError::internal("validate authenticated user", error))?;
    if !exists {
        return Err(AppError::unauthorized(
            "invalid_bearer_token",
            "The bearer token is invalid",
        ));
    }
    Ok(())
}

fn optional_fingerprint(headers: &HeaderMap) -> Result<Option<String>, AppError> {
    headers
        .get("x-device-fingerprint")
        .map(|value| {
            let value = value.to_str().map_err(|_| {
                AppError::bad_request(
                    "invalid_device_fingerprint",
                    "x-device-fingerprint is not a valid header value",
                )
            })?;
            validate_fingerprint(value).map_err(AppError::from)
        })
        .transpose()
}

fn invalid_transition_message(state: AttendanceState, action: AttendanceAction) -> &'static str {
    match (state, action) {
        (AttendanceState::OffDuty, AttendanceAction::ClockOut) => {
            "Cannot clock out before clocking in"
        }
        (_, AttendanceAction::ClockIn) => "Cannot clock in while already working",
        _ => "The attendance action is not valid for the current state",
    }
}

#[derive(Serialize)]
struct CachedState {
    state: AttendanceState,
    active_since: Option<DateTime<Utc>>,
    last_action_at: Option<DateTime<Utc>>,
}

async fn refresh_state_cache(state: &AppState, user_id: i64, row: &StateRow) {
    let cached = CachedState {
        state: row.state,
        active_since: row.active_since,
        last_action_at: row.last_action_at,
    };
    let value = match serde_json::to_string(&cached) {
        Ok(value) => value,
        Err(error) => {
            tracing::error!(user_id, %error, "could not serialize committed attendance state");
            return;
        }
    };
    if let Err(error) = state.redis.set_attendance_state(user_id, &value).await {
        tracing::warn!(user_id, %error, "could not refresh committed attendance state cache");
    }
}

#[cfg(test)]
mod tests {
    use chrono::{Days, NaiveDate};

    use super::calculate_streak;

    #[test]
    fn streak_can_end_today_or_yesterday() {
        let today = NaiveDate::from_ymd_opt(2026, 7, 19).expect("valid date");
        let yesterday = today.checked_sub_days(Days::new(1)).expect("valid date");
        let two_days_ago = yesterday
            .checked_sub_days(Days::new(1))
            .expect("valid date");
        assert_eq!(
            calculate_streak(&[today, yesterday, two_days_ago], today),
            3
        );
        assert_eq!(calculate_streak(&[yesterday, two_days_ago], today), 2);
        assert_eq!(calculate_streak(&[two_days_ago], today), 0);
    }
}
