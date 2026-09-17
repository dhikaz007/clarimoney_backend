CREATE TABLE IF NOT EXISTS refresh_token_history (
  token_hash CHAR(64) PRIMARY KEY,
  session_id UUID NOT NULL REFERENCES user_sessions(id) ON DELETE CASCADE,
  issued_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  consumed_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_refresh_token_history_session
  ON refresh_token_history (session_id);

INSERT INTO refresh_token_history (token_hash, session_id, expires_at)
SELECT refresh_token_hash, id, expires_at
FROM user_sessions
ON CONFLICT (token_hash) DO NOTHING;
