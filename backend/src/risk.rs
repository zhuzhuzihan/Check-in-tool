use chrono::{DateTime, Utc};
use serde_json::Value;

use crate::models::ClockRequest;

const MAX_CLIENT_DRIFT_MS: u64 = 60_000;
const MIN_TOUCH_DURATION_MS: i64 = 50;
const MAX_TOUCH_DURATION_MS: i64 = 10_000;
const MAX_TOUCH_SAMPLE_COUNT: i64 = 10_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RuleViolation {
    pub code: &'static str,
    pub message: &'static str,
}

impl RuleViolation {
    const fn new(code: &'static str, message: &'static str) -> Self {
        Self { code, message }
    }
}

#[derive(Debug)]
pub struct ValidatedClockRequest {
    pub fingerprint: String,
    pub client_time: DateTime<Utc>,
    pub touch_duration_ms: i32,
    pub touch_distance_px: f64,
    pub touch_sample_count: i32,
}

pub fn validate_clock_request(
    request: &ClockRequest,
    reject_emulators: bool,
) -> Result<ValidatedClockRequest, RuleViolation> {
    let fingerprint = validate_device(
        &request.device_fingerprint,
        &request.device_info,
        reject_emulators,
    )?;

    if !(MIN_TOUCH_DURATION_MS..=MAX_TOUCH_DURATION_MS).contains(&request.touch_duration_ms) {
        return Err(RuleViolation::new(
            "invalid_touch_duration",
            "touch_duration_ms must be between 50 and 10000",
        ));
    }
    if !request.touch_distance_px.is_finite() || request.touch_distance_px < 0.0 {
        return Err(RuleViolation::new(
            "invalid_touch_distance",
            "touch_distance_px must be finite and non-negative",
        ));
    }
    if !(1..=MAX_TOUCH_SAMPLE_COUNT).contains(&request.touch_sample_count) {
        return Err(RuleViolation::new(
            "invalid_touch_sample_count",
            "touch_sample_count must be between 1 and 10000",
        ));
    }
    let client_time =
        DateTime::from_timestamp_millis(request.client_timestamp).ok_or_else(|| {
            RuleViolation::new(
                "invalid_client_timestamp",
                "client_timestamp is outside the supported range",
            )
        })?;

    Ok(ValidatedClockRequest {
        fingerprint,
        client_time,
        touch_duration_ms: request.touch_duration_ms as i32,
        touch_distance_px: request.touch_distance_px,
        touch_sample_count: request.touch_sample_count as i32,
    })
}

pub fn validate_device(
    fingerprint: &str,
    device_info: &Value,
    reject_emulators: bool,
) -> Result<String, RuleViolation> {
    let fingerprint = validate_fingerprint(fingerprint)?;
    let info = device_info.as_object().ok_or_else(|| {
        RuleViolation::new("invalid_device_info", "device_info must be a JSON object")
    })?;
    match info.get("is_physical_device") {
        Some(physical) => {
            let physical = physical.as_bool().ok_or_else(|| {
                RuleViolation::new(
                    "invalid_device_info",
                    "device_info.is_physical_device must be a boolean",
                )
            })?;
            if reject_emulators && !physical {
                return Err(RuleViolation::new(
                    "emulator_rejected",
                    "emulated devices are not allowed",
                ));
            }
        }
        None if reject_emulators => {
            return Err(RuleViolation::new(
                "invalid_device_info",
                "device_info.is_physical_device is required",
            ));
        }
        None => {}
    }
    Ok(fingerprint)
}

pub fn validate_fingerprint(fingerprint: &str) -> Result<String, RuleViolation> {
    if fingerprint.len() != 64 || !fingerprint.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(RuleViolation::new(
            "invalid_device_fingerprint",
            "device_fingerprint must be exactly 64 hexadecimal characters",
        ));
    }
    Ok(fingerprint.to_ascii_lowercase())
}

pub fn validate_client_drift(
    client_time: DateTime<Utc>,
    server_time: DateTime<Utc>,
) -> Result<(), RuleViolation> {
    let drift = client_time
        .timestamp_millis()
        .abs_diff(server_time.timestamp_millis());
    if drift > MAX_CLIENT_DRIFT_MS {
        return Err(RuleViolation::new(
            "client_time_drift",
            "client clock differs from server time by more than 60 seconds",
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, TimeZone, Utc};
    use serde_json::json;
    use uuid::Uuid;

    use super::{validate_client_drift, validate_clock_request, validate_device};
    use crate::models::{AttendanceAction, ClockRequest};

    fn request() -> ClockRequest {
        ClockRequest {
            action: AttendanceAction::ClockIn,
            request_id: Uuid::new_v4(),
            device_fingerprint: "A".repeat(64),
            device_info: json!({"is_physical_device": true}),
            touch_duration_ms: 50,
            touch_distance_px: 0.0,
            touch_sample_count: 1,
            client_timestamp: 1_750_000_000_000,
        }
    }

    #[test]
    fn accepts_touch_boundaries_and_normalizes_fingerprint() {
        let mut input = request();
        input.touch_duration_ms = 10_000;
        input.touch_sample_count = 10_000;
        let validated = validate_clock_request(&input, true).expect("valid request");
        assert_eq!(validated.fingerprint, "a".repeat(64));
    }

    #[test]
    fn rejects_invalid_touch_risk_signals() {
        let mut input = request();
        input.touch_duration_ms = 49;
        assert_eq!(
            validate_clock_request(&input, true).unwrap_err().code,
            "invalid_touch_duration"
        );

        input.touch_duration_ms = 50;
        input.touch_distance_px = f64::INFINITY;
        assert_eq!(
            validate_clock_request(&input, true).unwrap_err().code,
            "invalid_touch_distance"
        );

        input.touch_distance_px = 0.0;
        input.touch_sample_count = 0;
        assert_eq!(
            validate_clock_request(&input, true).unwrap_err().code,
            "invalid_touch_sample_count"
        );
    }

    #[test]
    fn rejects_invalid_fingerprints_and_emulators() {
        assert_eq!(
            validate_device(&"g".repeat(64), &json!({}), false)
                .unwrap_err()
                .code,
            "invalid_device_fingerprint"
        );
        assert_eq!(
            validate_device(&"a".repeat(64), &json!({"is_physical_device": false}), true)
                .unwrap_err()
                .code,
            "emulator_rejected"
        );
        assert_eq!(
            validate_device(&"a".repeat(64), &json!({}), true)
                .unwrap_err()
                .code,
            "invalid_device_info"
        );
    }

    #[test]
    fn enforces_sixty_second_client_clock_drift() {
        let now = Utc
            .timestamp_millis_opt(1_750_000_000_000)
            .single()
            .expect("valid timestamp");
        assert!(validate_client_drift(now - Duration::seconds(60), now).is_ok());
        assert_eq!(
            validate_client_drift(now + Duration::milliseconds(60_001), now)
                .unwrap_err()
                .code,
            "client_time_drift"
        );
    }
}
