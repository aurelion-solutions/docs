# Notifications

Operating the four notification channels: provider selection,
secrets, and failure modes.

For the model see [Notifications concept](../concepts/notifications.md).
For the action contract see [Notifications reference](../reference/notifications.md).

## Provider selection

Each channel resolves its default provider from an environment
variable at action-call time:

| Env var | Default | Allowed values |
|---|---|---|
| `AURELION_NOTIFICATIONS_EMAIL_PROVIDER` | `file` | `file`, `smtp` |
| `AURELION_NOTIFICATIONS_SMS_PROVIDER` | `file` | `file`, `twilio` |
| `AURELION_NOTIFICATIONS_WEBHOOK_PROVIDER` | `file` | `file`, `http` |
| `AURELION_NOTIFICATIONS_INAPP_PROVIDER` | `file` | `file`, `eventbus` |

A request for an unregistered provider raises `Unsupported<Channel>ProviderError`
at action-call time.

## Email (SMTP)

Secrets under `notifications/email/smtp/`:

| Key | Required | Default | Notes |
|---|---|---|---|
| `host` | yes | — | SMTP server hostname. |
| `port` | no | `587` | Plain integer. |
| `username` | yes | — | |
| `password` | yes | — | |
| `from_address` | yes | — | RFC 5322 address used in the `From:` header. |
| `use_starttls` | no | `true` | `"false"` to disable STARTTLS. |

Missing required secret → action returns `sent=False` with
`reason="missing secret: notifications/email/smtp/<key>"`. The platform
boots without these — failures only surface on the first send.

The SMTP transaction is synchronous (blocks the event loop) and has a
30-second connect/IO timeout.

## SMS (Twilio)

Secrets under `notifications/sms/twilio/`:

| Key | Required | Notes |
|---|---|---|
| `account_sid` | yes | Twilio account SID. |
| `auth_token` | yes | Twilio auth token. |
| `from_number` | yes | E.164 phone number registered with Twilio. |

The provider talks to Twilio REST directly via `httpx` — no `twilio`
SDK dependency. A non-2xx response returns `sent=False` with
`reason="twilio <status>: <first 200 chars of body>"`.

## Webhook (HTTP)

No secrets. Configuration lives entirely in the action arguments:
`url` and `headers`. The provider sets `content-type: application/json`
and `user-agent: aurelion-notifications/0.1`; the caller can override
either via `message.headers`.

When the action carries `correlation_id`, the provider adds
`X-Aurelion-Correlation-Id: <value>`.

The HTTP client has a 15-second timeout. A 2xx response is success;
anything else returns `sent=False` with `status_code` and the first
200 chars of the response body in `reason`.

## In-app (eventbus)

No secrets. The provider emits an `EventEnvelope` on the configured MQ
events exchange (default `aurelion.events`, set via
`AURELION_MQ_EVENTS_EXCHANGE`). The action argument `routing_key` is
used verbatim as the event's `event_type` and RabbitMQ routing key.

Subscribers bind to whatever routing-key patterns they own. The
provider does not enforce a prefix.

Event payload contains:

```json
{
  "notification_id": "<uuid>",
  "template": "<template name>",
  "recipient_kind": "employee | nhi | operator",
  "recipient_id": "<id>",
  "subject": "<rendered subject>",
  "body": "<rendered body>",
  "link_to": null,
  "case_id": null,
  "ctx": { … },
  "created_at": "<iso8601>"
}
```

`notification_id` is assigned by the provider and returned in
`SendInappResult.notification_id` so the caller can join on it.

## Failure modes

| Symptom | Likely cause | Where to look |
|---|---|---|
| All sends return `sent=False` with `template_not_found` | Template file missing on disk | `aurelion-kernel/templates/notifications/<channel>/<name>.j2` |
| All sends return `sent=False` with `template_render_error` | A ctx key referenced by the template is missing | The template and the caller's `ctx` |
| Email returns `sent=False` with `missing secret: …` | SMTP credentials not provisioned | Secrets backend |
| SMS returns `sent=False` with `twilio <status>: …` | Twilio API rejected the request | Twilio dashboard, account balance, sender number |
| Webhook returns `sent=False` with `status_code >= 400` | Target rejected the payload | Target service logs |
| In-app `sent=False` | Event publication raised | Platform API logs; MQ broker health |
| Pipeline step fails with a non-`SendResult` exception | Transient infrastructure failure (DNS, socket) | Orchestrator will retry per the action's policy. |

## Testing locally

In dev the four channels default to `file` providers — they write
messages to disk and never reach an external system. To exercise the
real backends, set the env var(s) above and provide the matching
secrets.
