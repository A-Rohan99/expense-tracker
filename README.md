# Expense Tracker

A family expense tracker: a FastAPI backend over a double-entry ledger, and a
Flutter client you install from the browser with **Add to Home Screen**.

Tracks bank and cash accounts, credit cards with real billing cycles, loans
with EMI schedules, and a standing monthly income that posts itself.

---

## Quick start

You need Python 3.12+ and the Flutter SDK. Docker is optional but gives you the
same database engine production uses.

```bash
python -m venv .venv
.venv\Scripts\activate          # Windows;  source .venv/bin/activate elsewhere
pip install -r requirements-dev.txt
```

Create a `.env` in the repo root:

```bash
SECRET_KEY=paste-a-generated-value-here
ENVIRONMENT=development
```

Generate the key with:

```bash
python -c "import secrets; print(secrets.token_urlsafe(64))"
```

Then create the schema and start the API. `uvicorn` does not load `.env` on its
own, so either export the variables first or pass `--env-file`:

```bash
alembic upgrade head
uvicorn app.main:app --reload --env-file .env
```

The API is on http://localhost:8000, with docs at `/docs` (development only).

In a second terminal, run the client:

```bash
cd frontend
flutter pub get
flutter run -d chrome
```

### With Docker instead

Runs the API against Postgres, matching production:

```bash
docker compose up --build
```

---

## Layout

```
app/                 FastAPI backend
  main.py            app factory, middleware, health checks
  config.py          all settings; fails closed on anything production needs
  models.py          SQLAlchemy models — 8 tables
  schemas.py         Pydantic request/response shapes
  money.py           Decimal helpers; money never touches float
  auth.py            JWT, password hashing, token versioning
  errors.py          global exception handlers
  logging_config.py  structured logging + request correlation ids
  middleware.py      request context, auth rate limiting
  routers/           one module per resource
  services/          pure finance and recurring-income logic
migrations/          Alembic; owns the schema
tests/               pytest suite
frontend/            Flutter client (lib/, test/, web/)
```

---

## Configuration

Everything comes from environment variables. Anything dangerous to get wrong is
**required in production** — the process refuses to start rather than falling
back to a development default.

| Variable | Required | Default | Notes |
|---|---|---|---|
| `SECRET_KEY` | **always** | — | JWT signing key |
| `ENVIRONMENT` | no | `development` | `production` tightens the rules below |
| `DATABASE_URL` | in production | local SQLite | e.g. `postgresql+psycopg://user:pass@host:5432/db` |
| `ALLOWED_ORIGINS` | in production | localhost dev ports | comma-separated origins |
| `DOCS_ENABLED` | no | on outside production | serves `/docs`, `/redoc`, `/openapi.json` |
| `AUTH_RATE_LIMIT` | no | `20/minute` | budget of *failed* auth attempts per IP |
| `LOG_JSON` | no | on in production | JSON log lines |
| `LOG_LEVEL` | no | `INFO` | |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | no | `30` | |
| `REFRESH_TOKEN_EXPIRE_DAYS` | no | `7` | |
| `DB_POOL_SIZE` / `DB_MAX_OVERFLOW` | no | `5` / `10` | Postgres only |

`DATABASE_URL` deliberately has no production default: a container that forgot
it would otherwise boot against an ephemeral SQLite file and discard every
write on restart.

---

## Tests

```bash
pytest                        # backend, 139 tests
cd frontend && flutter test   # client, 79 tests
```

The backend suite runs on SQLite for speed. CI runs it against Postgres as
well, because dialect differences are exactly what would otherwise surface in
production.

---

## Deploying

The target is a container on a managed platform (Railway, Render, Fly) with
managed Postgres, and the Flutter web build served as static files.

**1. Backend.** Build and push the image; the entrypoint runs
`alembic upgrade head` before starting, so a failed migration stops the deploy
rather than leaving a process serving an old schema.

Set at minimum:

```
ENVIRONMENT=production
SECRET_KEY=<a fresh generated value, from the platform's secret store>
DATABASE_URL=<managed Postgres URL>
ALLOWED_ORIGINS=https://your-web-origin
```

Point the platform's health check at `/health`, and its readiness check at
`/health/ready`, which actually touches the database.

**2. Client.** The API URL is baked in at build time:

```bash
cd frontend
flutter build web --release \
  --dart-define=API_BASE_URL=https://your-api-host/api/v1
```

Serve `build/web/` as static files. It must be **https** — browsers block
mixed content, so an http API from an https page will fail silently.

**3. Install it.** Open the URL on a phone and use *Add to Home Screen*.

---

## Schema changes

Alembic owns the schema. `create_all` runs only outside production, and only as
a convenience for a fresh checkout — it can add a missing table but never alter
an existing one.

```bash
# after editing app/models.py
alembic revision --autogenerate -m "what changed"
alembic upgrade head
```

`alembic check` fails if the models and migrations have drifted; CI runs it.

---

## Notes

- **Money is `Decimal` everywhere.** Never cast it to `float`: Postgres rounds
  on write where SQLite does not, so a float round-trip makes the same inputs
  produce different balances on the two backends. Use `app/money.py`.
- **Derived values are derived.** Credit-card outstanding and loan EMI state
  are computed from the ledger on read, never stored, so they cannot drift.
- **Every error carries a `request_id`**, echoed as `X-Request-ID`, which ties
  a user's report to the exact server log line.
- **Fonts are bundled, not fetched.** Space Grotesk and Inter live in
  `frontend/assets/fonts/`, subset to the characters the UI actually uses
  (1.5 MB → 302 KB). Nothing is requested from fonts.gstatic.com, so the
  installed app looks the same offline.
