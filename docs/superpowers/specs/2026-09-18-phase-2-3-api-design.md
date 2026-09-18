# ClariMoney Phase 2/3 API Design

## Goal

Extend expense-only backend into unified Income + Expense transactions, then add deterministic comparative financial APIs.

## Phase 2

### Unified transaction

Every transaction stores:

- `type`: `income` or `expense`.
- `category_id`: required for both types.
- positive `amount` with maximum two decimal places.
- full UTC ISO-8601 `date`, example `2026-09-15T08:30:00.000Z`.
- optional trimmed `note`, maximum 500 characters.
- `created_at`.

Income categories are separate from expense categories. Starter income categories: Salary, Bonus, Freelance, Gift, Other. Existing expense rows backfill as `expense`.

### Category lifecycle

Categories gain `type`, `status`, and `origin`:

- `type`: `income` or `expense`.
- `status`: `active` or `archived`.
- `origin`: `system` or `user_created`.

Names are trimmed, non-empty, maximum 50 characters, case-insensitive unique across active and archived categories per user/type. Rename preserves ID. Archive blocks new assignment but preserves historical references. Hard delete remains unsupported.

### Transaction APIs

- `GET /api/v1/transactions?page=1&limit=10&type=all&period=this_month&category_id=&search=`
- `POST /api/v1/transactions`
- `GET /api/v1/transactions/:id`
- `PUT /api/v1/transactions/:id`
- `DELETE /api/v1/transactions/:id`

Create/update body:

```json
{
  "type": "income",
  "category_id": "uuid",
  "amount": 12500000,
  "date": "2026-09-15T08:30:00.000Z",
  "note": "Monthly salary"
}
```

Filter semantics: case-insensitive partial search over note/category name, filters combine with AND, ordering `date DESC, created_at DESC`, period values `this_month`/`previous_month`.

### Summary API

`GET /api/v1/summary/overview?period=this_month` returns total income, total expense, net cash flow availability/value, expense breakdown, and largest expense category.

Net cash flow is unavailable when period has expenses but no income. Income-only period has zero spending and available net cash flow.

## Phase 3

### Comparison period

Backend derives equivalent previous period. Full month compares full previous month. Partial current period compares same elapsed day range in previous month. Client cannot choose arbitrary comparison period.

### Comparison APIs

- `GET /api/v1/summary/comparison?period=this_month`
- `GET /api/v1/summary/comparison/categories?period=this_month`
- `GET /api/v1/categories/:id/comparison?period=this_month`

Comparison response includes current/comparison period ranges, current/previous values, absolute change, percentage change only for non-zero valid baselines, and comparison availability.

Classification comparison matches persistent category ID. Current category name is displayed. Archived historical categories remain eligible.

Change drivers rank `ABS(current - previous)` descending, return maximum three, include increases/decreases, and provide no explanation or recommendation.

## Date and money contract

- Request/response datetime format: full ISO-8601 with `T`, timezone, and milliseconds where emitted.
- DB type: `TIMESTAMPTZ`.
- Server normalizes date calculations to UTC.
- Amount remains positive magnitude; transaction type determines direction.
- Monetary arithmetic uses PostgreSQL numeric values, not binary floating point.

## Compatibility

- Existing expense records backfill to `type=expense`.
- Existing expense category IDs remain valid.
- Old expense clients without `type`/`note` are temporarily accepted as `expense` only during migration window, then removed after mobile rollout.
- Existing auth/session behavior remains unchanged.

## Out of scope

- Budgeting, saving goals, forecasting, bank integrations, recurring transactions, investment, shared finance, multi-currency, FX.
- Arbitrary comparison periods.
- Transaction-to-transaction matching.
- Financial advice or health scoring.
