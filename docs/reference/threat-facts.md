# Threat Fact

A risk signal attached to a Subject: risk score, active threat indicators, recent authentication anomalies. Used by the PDP to escalate or block access decisions. One record per Subject — upserted on each signal update.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `subject_id` | UUID | FK to Subject (unique) |
| `account_id` | UUID | Associated account (optional) |
| `risk_score` | float | 0.0–1.0 |
| `active_indicators` | string[] | Active threat indicators (e.g. `account_takeover`, `impossible_travel`) |
| `failed_auth_count` | int | Recent failed authentication count |
| `last_login_at` | datetime | Last observed login |
| `observed_at` | datetime | When the signal was observed |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/threat-facts` | List, filter by `subject_id`, `account_id`, `min_risk_score` |
| `GET` | `/api/v0/threat-facts/{id}` | Get by ID |
| `PUT` | `/api/v0/threat-facts/{subject_id}` | Upsert by subject — 201 on first insert, 200 on update |

## CLI

| Command | Description |
|---|---|
| `al inventory threat-facts list` | List all threat facts |
| `al inventory threat-facts list --subject <id>` | Filter by subject |
| `al inventory threat-facts list --min-risk-score <0.0–1.0>` | Filter by risk score |
| `al inventory threat-facts get <id>` | Get by fact ID |
| `al inventory threat-facts upsert <subject_id> --risk-score <score>` | Upsert signal |
| `al inventory threat-facts upsert <subject_id> --risk-score <score> --indicator <name>` | Upsert with indicator (repeatable) |
