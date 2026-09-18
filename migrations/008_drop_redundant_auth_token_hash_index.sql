-- Legacy cleanup for databases that ran an earlier form of migration 007.
-- Current migration 007 relies on auth_tokens_token_hash_key for token_hash
-- lookup and does not create idx_auth_tokens_hash.
DROP INDEX IF EXISTS public.idx_auth_tokens_hash;
