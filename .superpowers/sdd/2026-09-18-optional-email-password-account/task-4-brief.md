### Task 4: Permanent account deletion

**Files:**
- Create: `routes/api/v1/auth/account/index.dart`
- Modify: `docs/api.md`
- Test: `test/routes/account_routes_test.dart`

**Interfaces:**
- `DELETE /api/v1/auth/account` requires Bearer access token and body `{ "password": "..." }`.

- [ ] Verify current password with existing `PasswordUtils.verify`.
- [ ] Return `401` for wrong password without deleting data.
- [ ] Delete user in transaction; rely on FK cascades for categories, transactions, sessions, and auth tokens.
- [ ] Return `200` confirmation only after commit.
- [ ] Test valid deletion, wrong password, missing password, and cascade cleanup.
- [ ] Document irreversible behavior.
