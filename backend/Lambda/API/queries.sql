-- name: GetDeviceByDeviceID :one
SELECT user_id, device_id, platform, fcm_token, is_active, updated_at
FROM devices
WHERE device_id = $1
LIMIT 1;

-- name: UpsertDevice :exec
INSERT INTO devices (user_id, device_id, platform, fcm_token, is_active, updated_at)
VALUES ($1, $2, $3, $4, TRUE, NOW())
ON CONFLICT (user_id, device_id)
DO UPDATE SET
    fcm_token = EXCLUDED.fcm_token,
    is_active = TRUE,
    updated_at = NOW();





