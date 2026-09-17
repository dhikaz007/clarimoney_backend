ALTER TABLE user_sessions
  DROP CONSTRAINT IF EXISTS user_sessions_user_id_fkey;

ALTER TABLE user_sessions
  ADD CONSTRAINT user_sessions_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES users(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;

ALTER TABLE refresh_token_history
  DROP CONSTRAINT IF EXISTS refresh_token_history_session_id_fkey;

ALTER TABLE refresh_token_history
  ADD CONSTRAINT refresh_token_history_session_id_fkey
  FOREIGN KEY (session_id) REFERENCES user_sessions(id)
  ON DELETE CASCADE ON UPDATE CASCADE;
