# Notifications

Aurelion ships outbound notifications through four channels — **email**,
**SMS**, **webhook**, and **in-app** — exposed to pipelines as engine
actions, with delivery handled by per-channel platform providers.

The shape is the same for every channel:

```
pipeline step
  │
  │  notifications.send_<channel>(template, ctx, …)
  ▼
engine action  ──▶  template engine  ──▶  rendered message
                                              │
                                              ▼
                                       channel factory
                                              │
                                              ▼
                                       configured provider
                                              │
                                              ▼
                                       external system
```

## Why a single shape for four channels

Email, SMS, webhook, and in-app are different transport mechanics, but
the operator model is identical: *a pipeline step describes who to
notify, what template to render, and which context to render it with*.
Keeping the engine action contract uniform means a tenant cartridge
declares "notify by email" and "notify by SMS" the same way — only the
channel slug and the per-channel arguments differ.

The split between engine and platform follows the standard kernel
layering:

| Layer | Owns |
|---|---|
| Engine (`engines/notifications/`) | The four `notifications.send_*` actions, the template engine, the action-result schemas. |
| Platform (`platform/notifications/<channel>/`) | The `<Channel>Sender` Protocol, per-channel `Message` / `SendResult` dataclasses, the factory that resolves a provider by name, and the providers themselves. |

The engine never imports a concrete provider. The factory is the only
seam — a runtime selects a provider through env (`AURELION_NOTIFICATIONS_<CHANNEL>_PROVIDER`),
and the engine resolves the default at action-call time.

## Template engine

Templates are Jinja2 files under
`aurelion-kernel/templates/notifications/<channel>/<name>.j2`, with two
named blocks:

```jinja
{% block subject %}…{% endblock %}
{% block body %}…{% endblock %}
```

`subject` and `body` are rendered independently and returned as a
`RenderedTemplate` pair. SMS templates may set only `body`; webhook
templates produce a body fragment that the provider wraps into a JSON
envelope.

Templates use `StrictUndefined` — a missing context key is a hard
error, never a silent empty string. A missing template file is also a
hard error; the engine action returns `sent=False` with a
`template_not_found` reason and the pipeline step's `on_error` policy
decides whether to fail the step.

Templates are immutable at runtime. There is no template-editing API.

## Delivery model: result over exception

A delivery failure is a `SendResult` with `sent=False` and a `reason`
string. An infrastructure failure (DNS timeout, unhandled exception)
raises and is retried by the pipeline orchestrator's retry policy.
The two are deliberately split:

- **`sent=False`** — the provider talked to the external system and got
  a structured failure (HTTP 4xx, SMTP NDR, Twilio 400). The action
  returns the failure; the pipeline step's `on_error` policy decides.
- **Raised exception** — the provider could not even talk to the
  external system. The orchestrator retries per the action policy.

## Channels

### Email

`notifications.send_email` renders the template and hands an
`EmailMessage` to the configured `EmailSender`. Providers:

| Provider | Use |
|---|---|
| `file` | Default in dev/test. Writes the message to disk for inspection. |
| `smtp` | Production SMTP via `smtplib` with optional STARTTLS. |

The SMTP provider reads its config from kernel secrets under
`notifications/email/smtp/` — missing credentials surface as
`sent=False` with a `missing secret: …` reason, not an exception.

### SMS

`notifications.send_sms` renders the template (body block only) and
hands an `SmsMessage` to the configured `SmsSender`. Providers:

| Provider | Use |
|---|---|
| `file` | Default in dev/test. |
| `twilio` | Production via Twilio REST. Reads `notifications/sms/twilio/*` secrets. |

SMS `to` is a single E.164 phone number per call. Length validation is
provider-specific; the engine does not enforce a maximum.

### Webhook

`notifications.send_webhook` renders the template and POSTs a JSON
payload to the supplied URL. The payload combines the verbatim `ctx`
with `_template`, `_subject`, and `_body` (the latter two from the
rendered template). Providers:

| Provider | Use |
|---|---|
| `file` | Default in dev/test. |
| `http` | Production HTTPS POST via `httpx`. Sets `content-type: application/json` and `X-Aurelion-Correlation-Id` when a correlation id is provided. |

A 2xx response is a success; any other status returns `sent=False`
with the status code and the first 200 chars of the response body.

### In-app

`notifications.send_inapp` renders the template and emits an event on
the configured MQ exchange. The routing key is supplied by the caller
(`routing_key` action argument); product-side subscribers bind to the
keys they own and persist their own inbox rows. Providers:

| Provider | Use |
|---|---|
| `file` | Default in dev/test. Appends the message to a file. |
| `eventbus` | Production. Emits an `EventEnvelope` on `aurelion.events` via `EventService.emit`. |

In-app is the only channel where the provider does not deliver to an
external system — it emits an event and lets a downstream consumer
persist the inbox row. That keeps the kernel out of inbox storage
while still giving renderers a real-time notification stream.

## Where to go next

- [Notifications reference](../reference/notifications.md) — actions,
  arguments, result envelopes, provider names.
- [Notifications operations](../operations/notifications.md) — env
  variables and secret keys per channel and provider.
