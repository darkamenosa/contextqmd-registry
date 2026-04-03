# PostgreSQL Tuning

This repo runs PostgreSQL 18 as a Kamal accessory on the same host as the app,
job worker, Vite SSR process, and proxy.

Current production host shape:

- `4 vCPU`
- `7.5 GiB RAM`
- `0 swap`

Because the database is not on a dedicated server, tuning should stay
conservative.

## PgBouncer

Production app traffic should go through PgBouncer first to reduce backend
Postgres connection pressure.

Communication flow on this Kamal host:

```text
Rails web/job container
  -> contextqmd_registry-pgbouncer:5432
  -> PgBouncer container
  -> contextqmd_registry-db:5432
  -> PostgreSQL container
```

These are separate Docker containers, but Kamal puts them on the same Docker
network. Inside that network, containers can reach each other by container name
or network alias. So:

- Rails connects to `contextqmd_registry-pgbouncer`
- PgBouncer connects to `contextqmd_registry-db`
- the host-exposed port `127.0.0.1:6432` is only for direct debugging from the
  server, not for normal app traffic

Current production split:

- Rails app containers default to `DB_HOST=contextqmd_registry-pgbouncer`
- Direct Postgres remains available at `contextqmd_registry-db`
- `kamal dbc` is intentionally pinned to the direct host for maintenance work
- web boot uses `DB_DIRECT_HOST` for `db:prepare`, so schema checks and
  migrations do not run through transaction pooling

PgBouncer runs in `transaction` pooling mode with conservative limits for this
host:

- `auth_type = scram-sha-256`
- `default_pool_size = 5`
- `min_pool_size = 1`
- `reserve_pool_size = 2`
- `max_client_conn = 500`
- `ignore_startup_parameters = extra_float_digits`
- `max_prepared_statements = 200`

Rails production config disables Active Record advisory locks so deploy-time
tasks do not rely on session-level locks while running through the pooler, and
it caps `statement_limit = 200` to match the PgBouncer prepared-statement cache.

### First rollout and auth

Two operational details matter here:

- `kamal deploy` does not boot new accessories. `kamal setup` does, or you must
  run `bin/kamal accessory boot pgbouncer --primary` yourself the first time.
- This `edoburu/pgbouncer` image defaults to `auth_type = md5`. Our Postgres 18
  role password is stored as `SCRAM-SHA-256`, so production PgBouncer must set
  `AUTH_TYPE=scram-sha-256` or Rails connections will fail with `wrong password type`.

Safe first-time PgBouncer rollout order:

```bash
bin/kamal accessory boot pgbouncer --primary
bin/kamal deploy
```

If you change PgBouncer env or image later, use:

```bash
bin/kamal accessory reboot pgbouncer --primary
```

Quick verification after boot/reboot:

```bash
bin/kamal accessory logs pgbouncer --primary --lines=40
curl -sS -o /dev/null -w '%{http_code} %{time_total}\n' https://contextqmd.com/up
```

### Secret

PgBouncer should receive its backend database URLs from the accessory env var
`DATABASE_URLS`, provided via Kamal secrets rather than clear config.

That secret value should contain a comma-separated list of production database
URLs, for example:

```text
postgres://contextqmd_registry:...@contextqmd_registry-db/contextqmd_registry_production,postgres://contextqmd_registry:...@contextqmd_registry-db/contextqmd_registry_production_cache,postgres://contextqmd_registry:...@contextqmd_registry-db/contextqmd_registry_production_queue,postgres://contextqmd_registry:...@contextqmd_registry-db/contextqmd_registry_production_cable,postgres://contextqmd_registry:...@contextqmd_registry-db/contextqmd_registry_production_analytics
```

Current first-pass target values:

- `shared_buffers = 768MB`
- `effective_cache_size = 3GB`
- `work_mem = 8MB`
- `maintenance_work_mem = 256MB`
- `max_wal_size = 2GB`
- `checkpoint_completion_target = 0.9`
- `wal_compression = 'pglz'`
- `random_page_cost = 1.1`
- `effective_io_concurrency = 200`
- `track_io_timing = on`

Why these values:

- PostgreSQL docs recommend `shared_buffers` as a starting point around 25% of
  RAM on dedicated servers, but this host is shared with Rails containers, so
  `768MB` is a safer step up from the default `128MB`.
- `effective_cache_size` is only a planner hint. `3GB` is a conservative guess
  for the cache likely available to queries on this shared box.
- `work_mem` is per operation, not per connection. Keep it modest because query
  memory multiplies across sessions.
- `maintenance_work_mem` helps `VACUUM`, `CREATE INDEX`, and other maintenance
  work more than normal OLTP queries, so it can be higher than `work_mem`.
- `max_wal_size` and `checkpoint_completion_target` reduce aggressive
  checkpointing and smooth write pressure.
- `wal_compression` reduces WAL volume at some CPU cost, which is a reasonable
  tradeoff on this host.
- `random_page_cost` and `effective_io_concurrency` make the planner and I/O
  model better match modern local storage.

## Apply With Kamal

Run these from the repo root:

```bash
bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM SET shared_buffers = '768MB';"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM SET effective_cache_size = '3GB';"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM SET work_mem = '8MB';"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM SET maintenance_work_mem = '256MB';"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM SET max_wal_size = '2GB';"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM SET checkpoint_completion_target = '0.9';"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM SET wal_compression = 'pglz';"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM SET random_page_cost = '1.1';"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM SET effective_io_concurrency = '200';"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM SET track_io_timing = 'on';"
```

Then reboot the DB accessory once:

```bash
bin/kamal accessory reboot db --primary
```

## Verify

After reboot:

```bash
bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "SHOW shared_buffers; SHOW effective_cache_size; SHOW work_mem; SHOW maintenance_work_mem; SHOW max_wal_size; SHOW checkpoint_completion_target; SHOW wal_compression; SHOW random_page_cost; SHOW effective_io_concurrency; SHOW track_io_timing;"
```

Check app-side pressure:

```bash
bin/kamal app exec --reuse --primary --roles=web \
  "bin/rails runner 'puts({ active_connections: ActiveRecord::Base.connection.select_value(\"SELECT count(*) FROM pg_stat_activity\"), max_connections: ActiveRecord::Base.connection.select_value(\"SHOW max_connections\") }.to_json)'"
```

Check queue state:

```bash
bin/kamal app exec --reuse --primary --roles=job \
  "bin/rails runner 'puts({ ready: SolidQueue::ReadyExecution.count, ready_by_queue: SolidQueue::ReadyExecution.joins(:job).group(\"solid_queue_jobs.queue_name\").count }.to_json)'"
```

## Reset

If you need to remove these overrides later:

```bash
bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM RESET shared_buffers;"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM RESET effective_cache_size;"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM RESET work_mem;"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM RESET maintenance_work_mem;"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM RESET max_wal_size;"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM RESET checkpoint_completion_target;"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM RESET wal_compression;"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM RESET random_page_cost;"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM RESET effective_io_concurrency;"

bin/kamal accessory exec db --primary --reuse -- \
  psql -U contextqmd_registry -d contextqmd_registry_production \
  -c "ALTER SYSTEM RESET track_io_timing;"

bin/kamal accessory reboot db --primary
```
