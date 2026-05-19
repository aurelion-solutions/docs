# Notifications

Four pipeline-callable engine actions deliver notifications through
four channels. For the model and rationale see
[Notifications](../concepts/notifications.md).

## Engine actions

All four actions live under the `notifications` engine and are
non-idempotent. They render a Jinja2 template, build a channel-specific
message, delegate to the channel's factory-resolved provider, and
return a typed result envelope.

| Engine | Action | Result schema |
|---|---|---|
| `notifications` | `send_email` | `SendEmailResult` |
| `notifications` | `send_sms` | `SendSmsResult` |
| `notifications` | `send_webhook` | `SendWebhookResult` |
| `notifications` | `send_inapp` | `SendInappResult` |

### `notifications.send_email`

Arguments:

| Field | Type | Notes |
|---|---|---|
| `template` | string | Template name under `templates/notifications/email/<template>.j2`. |
| `to` | tuple of string | One or more RFC 5322 addresses. |
| `ctx` | mapping | Template context. Missing keys raise a render error → `sent=False` with `reason="template_render_error: …"`. |
| `locale` | string | ISO 639-1, default `en`. |
| `correlation_id` | string \| null | Propagated to provider logs / headers. |

Result fields:

| Field | Notes |
|---|---|
| `sent` | `true` only when the provider acknowledged delivery. |
| `provider` | Resolved provider name (`file`, `smtp`, …) or `unrendered` when rendering failed. |
| `reason` | Populated only when `sent=false`. |
| `provider_message_id` | Upstream message id when the provider returns one. `null` for `file`. |

### `notifications.send_sms`

Arguments:

| Field | Type | Notes |
|---|---|---|
| `template` | string | Under `templates/notifications/sms/<template>.j2`. SMS templates use the `body` block; if the template only sets `subject`, the engine falls back to that. |
| `to` | string | E.164-format phone number. |
| `ctx` | mapping | Template context. |
| `locale` | string | Default `en`. |
| `correlation_id` | string \| null | |

Result fields mirror `SendEmailResult` (`provider_message_id` is the
upstream id, e.g. Twilio SID).

### `notifications.send_webhook`

Arguments:

| Field | Type | Notes |
|---|---|---|
| `url` | string | Webhook target. |
| `template` | string | Under `templates/notifications/webhook/<template>.j2`. |
| `ctx` | mapping | Verbatim payload base. After rendering, the engine adds `_template`, `_subject` (if non-empty), and `_body` (if non-empty) to the payload. |
| `headers` | mapping | Merged with provider defaults (`content-type: application/json`, `user-agent`, `X-Aurelion-Correlation-Id`). |
| `correlation_id` | string \| null | |

Result fields:

| Field | Notes |
|---|---|
| `sent` | `true` on HTTP 2xx. |
| `provider` | `file`, `http`, or `unrendered`. |
| `reason` | First 200 chars of the response body when `sent=false`. |
| `status_code` | HTTP status, or `null` for the `file` provider. |

### `notifications.send_inapp`

Arguments:

| Field | Type | Notes |
|---|---|---|
| `template` | string | Under `templates/notifications/inapp/<template>.j2`. |
| `recipient_kind` | enum | `employee`, `nhi`, or `operator`. |
| `recipient_id` | string | Recipient identifier interpreted by the consuming UI. |
| `routing_key` | string | MQ routing key the `eventbus` provider emits on. Subscribers bind to a pattern containing this key. |
| `ctx` | mapping | Forwarded verbatim in the event payload. |
| `link_to` | string \| null | Optional deep link the renderer uses. |
| `case_id` | string \| null | Optional product-side correlation id, forwarded untouched. |
| `correlation_id` | string \| null | |

Result fields:

| Field | Notes |
|---|---|
| `sent` | `true` when the event was emitted. |
| `provider` | `file` or `eventbus`. |
| `reason` | Populated only when `sent=false`. |
| `notification_id` | UUID assigned by the provider; carried verbatim in the emitted event payload so consumers can join on it. |

## Providers per channel

The factory exposes the same shape for every channel: register a
provider name, look one up by name, return the env-selected default.

| Channel | Default env var | Built-in providers |
|---|---|---|
| email | `AURELION_NOTIFICATIONS_EMAIL_PROVIDER` | `file`, `smtp` |
| sms | `AURELION_NOTIFICATIONS_SMS_PROVIDER` | `file`, `twilio` |
| webhook | `AURELION_NOTIFICATIONS_WEBHOOK_PROVIDER` | `file`, `http` |
| inapp | `AURELION_NOTIFICATIONS_INAPP_PROVIDER` | `file`, `eventbus` |

Default value when the env var is unset: `file`.

### Provider Protocol

Each channel defines a `Protocol` an external implementation can
satisfy:

```python
class EmailSender(Protocol):
    name: str
    async def send(self, message: EmailMessage) -> EmailSendResult: ...
```

`SmsSender`, `WebhookSender`, and `InAppSender` share the same shape
with channel-specific `Message` / `SendResult` dataclasses (subject and
body for email; body only for SMS; URL + payload + headers for
webhook; recipient kind + routing key + body + ctx for in-app).

Implementations:

- **Return** a `SendResult` for delivery failures (HTTP 4xx, SMTP NDR,
  vendor 400). The engine surfaces this as `sent=False`.
- **Raise** for transient infrastructure errors (DNS timeout,
  unreachable host, unhandled exception). The orchestrator's retry
  policy handles those.

## Templates

Templates live under
`aurelion-kernel/templates/notifications/<channel>/<name>.j2` and
contain two Jinja2 blocks named `subject` and `body`. Strict undefined
is on — referencing an unprovided context key fails the render.

Channel layout:

| Channel | Folder | Notes |
|---|---|---|
| email | `templates/notifications/email/` | Subject + body. |
| sms | `templates/notifications/sms/` | Body block only is used; subject is ignored if set. |
| webhook | `templates/notifications/webhook/` | Rendered fragments are merged into the payload under `_subject` / `_body`. |
| inapp | `templates/notifications/inapp/` | Subject + body are passed through to subscribers in the event payload. |

A template name is just the filename without the `.j2` extension —
e.g. `welcome` maps to `templates/notifications/email/welcome.j2`.

## See also

- [Notifications concept](../concepts/notifications.md)
- [Notifications operations](../operations/notifications.md) —
  per-runtime config (env vars, secrets).
- [Engine action registry](engine-action-registry.md) — every
  registered engine action.
