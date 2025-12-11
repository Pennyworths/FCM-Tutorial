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


-- name: ListActiveDevicesByPlatforms :many
SELECT user_id, device_id, platform, fcm_token, is_active, updated_at
FROM devices
WHERE user_id = $1 AND is_active = TRUE AND platform IN ('android', 'ios');

-- name: CreateTestRun :exec
INSERT INTO test_runs (nonce, user_id, status, created_at)
VALUES ($1, $2, 'PENDING', NOW())
ON CONFLICT (nonce) DO NOTHING;

-- name: AckTestRun :one
UPDATE test_runs
SET status = 'ACKED', acked_at = NOW()
WHERE nonce = $1 AND status = 'PENDING'
RETURNING nonce, user_id, status, created_at, acked_at;

-- name: GetTestRunByNonce :one
SELECT nonce, user_id, status, created_at, acked_at
FROM test_runs
WHERE nonce = $1
LIMIT 1;

-- name: GetUserByEmail :one
SELECT user_id, email, created_at, updated_at
FROM users
WHERE email = $1
LIMIT 1;

-- name: GetUserByUserID :one
SELECT user_id, email, created_at, updated_at
FROM users
WHERE user_id = $1
LIMIT 1;

-- name: UpsertUserByEmail :one
INSERT INTO users (user_id, email, created_at, updated_at)
VALUES (
    -- Generate user_id: use email hash (will be generated in Go code)
    $2,  -- user_id (passed as second parameter)
    $1,  -- email
    NOW(),
    NOW()
)
ON CONFLICT (email)
DO UPDATE SET
    updated_at = NOW()
RETURNING user_id, email, created_at, updated_at;
