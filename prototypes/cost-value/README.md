# AIQuota cost/value prototype

Interactive product-language study for presenting API-equivalent usage value
without implying that the user received an additional bill.

From the repository root:

```bash
make dev-local SITE_ROOT=prototypes/cost-value PORT=8131
```

The prototype explores:

- `Cost` — immediate, but easy to mistake for actual billing.
- `Usage value` — the recommended default.
- `Subscription value` — useful when the user supplies a monthly plan price.
- A `Value / Tokens` switch to keep the underlying usage visible.

The generated visual reference is saved alongside this prototype as
`concept-reference.png`.
