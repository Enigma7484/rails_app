# Move Production Postgres From Render To Neon

This app is ready to use Neon as production Postgres through `DATABASE_URL`.

## Required URLs

- `RENDER_DATABASE_URL`: the current Render Postgres external connection string.
- `NEON_DATABASE_URL`: the Neon connection string for the target database.

Use Neon's pooled connection string for the deployed Rails web service. Neon pooled URLs include `-pooler` in the hostname. Keep `sslmode=require` in the URL.

## One-time data copy

Run this locally from `rails_app` after installing PostgreSQL client tools:

```bash
export RENDER_DATABASE_URL="postgres://..."
export NEON_DATABASE_URL="postgresql://...?sslmode=require"
script/migrate_render_postgres_to_neon
```

The script:

- creates a local dump in `tmp/`
- restores it into Neon
- runs Rails migrations against Neon

Keep the dump file until the deployed app has been verified.

## Render cutover

In the Render web service dashboard:

1. Replace `DATABASE_URL` with the Neon pooled connection string.
2. Keep `RAILS_MASTER_KEY`, `AGENT_SERVICE_URL`, and other existing app env vars unchanged.
3. Redeploy the web service.
4. Check the deploy logs for a successful `rails db:migrate`.

Do not delete the Render Postgres database until production has been verified against Neon.

## Verification

After redeploy:

- sign in
- open the dashboard
- open an existing upload
- upload a CSV or XLSX
- run analysis
- confirm subscriptions and settings still load

Then pause or delete the old Render Postgres instance.
