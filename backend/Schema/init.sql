-- Devices table: stores FCM device registrations
CREATE TABLE IF NOT EXISTS devices (
  id          SERIAL PRIMARY KEY,
  user_id     TEXT NOT NULL,
  device_id   TEXT NOT NULL,
  platform    TEXT NOT NULL, -- 'android'
  fcm_token   TEXT NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, device_id)
);

-- Test runs table: tracks FCM message delivery status
CREATE TABLE IF NOT EXISTS test_runs (
  nonce       TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  status      TEXT NOT NULL, -- 'PENDING' or 'ACKED'
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acked_at    TIMESTAMPTZ
);