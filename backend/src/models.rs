use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[serde(rename_all = "snake_case")]
#[sqlx(type_name = "attendance_status", rename_all = "snake_case")]
pub enum AttendanceState {
    OffDuty,
    OnDuty,
    OnBreak,
}

impl AttendanceState {
    pub fn transition(self, action: AttendanceAction) -> Option<Self> {
        match (self, action) {
            (Self::OffDuty, AttendanceAction::ClockIn) => Some(Self::OnDuty),
            (Self::OnDuty | Self::OnBreak, AttendanceAction::ClockOut) => Some(Self::OffDuty),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[serde(rename_all = "snake_case")]
#[sqlx(type_name = "attendance_action", rename_all = "snake_case")]
pub enum AttendanceAction {
    ClockIn,
    ClockOut,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ClockRequest {
    pub action: AttendanceAction,
    pub request_id: Uuid,
    pub device_fingerprint: String,
    pub device_info: Value,
    pub touch_duration_ms: i64,
    pub touch_distance_px: f64,
    pub touch_sample_count: i64,
    pub client_timestamp: i64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TrustDeviceRequest {
    pub device_fingerprint: String,
    pub device_info: Value,
}

#[derive(Debug, Serialize)]
pub struct Data<T> {
    pub data: T,
}

impl<T> Data<T> {
    pub const fn new(data: T) -> Self {
        Self { data }
    }
}

#[derive(Debug, Serialize)]
pub struct ServerTime {
    pub server_time: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
pub struct Dashboard {
    pub display_name: String,
    pub state: AttendanceState,
    pub server_time: DateTime<Utc>,
    pub today_worked_ms: i64,
    pub active_since: Option<DateTime<Utc>>,
    pub last_action_at: Option<DateTime<Utc>>,
    pub weekly_hours: Vec<DailyHours>,
    pub streak_days: i64,
    pub device_trusted: bool,
}

#[derive(Debug, Serialize)]
pub struct DailyHours {
    pub day: NaiveDate,
    pub worked_ms: i64,
}

#[derive(Debug, Serialize)]
pub struct TrustDeviceResponse {
    pub device_fingerprint: String,
    pub trusted_at: DateTime<Utc>,
    pub device_trusted: bool,
}

#[derive(Debug, Serialize)]
pub struct DevTokenResponse {
    pub token: String,
    pub token_type: &'static str,
    pub expires_at: DateTime<Utc>,
    pub user_id: i64,
}

#[derive(Debug, Serialize)]
pub struct HealthStatus {
    pub status: &'static str,
}

#[derive(Debug, Serialize)]
pub struct ReadinessStatus {
    pub status: &'static str,
    pub postgres: &'static str,
    pub redis: &'static str,
}

#[cfg(test)]
mod tests {
    use super::{AttendanceAction, AttendanceState};

    #[test]
    fn state_machine_covers_every_state_and_action() {
        use AttendanceAction::{ClockIn, ClockOut};
        use AttendanceState::{OffDuty, OnBreak, OnDuty};

        assert_eq!(OffDuty.transition(ClockIn), Some(OnDuty));
        assert_eq!(OffDuty.transition(ClockOut), None);
        assert_eq!(OnDuty.transition(ClockIn), None);
        assert_eq!(OnDuty.transition(ClockOut), Some(OffDuty));
        assert_eq!(OnBreak.transition(ClockIn), None);
        assert_eq!(OnBreak.transition(ClockOut), Some(OffDuty));
    }

    #[test]
    fn duplicate_clock_in_is_rejected() {
        assert_eq!(
            AttendanceState::OnDuty.transition(AttendanceAction::ClockIn),
            None
        );
    }

    #[test]
    fn clock_out_without_clock_in_is_rejected() {
        assert_eq!(
            AttendanceState::OffDuty.transition(AttendanceAction::ClockOut),
            None
        );
    }
}
