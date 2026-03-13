# How to connect an application

This guide walks through registering a new application in Aurelion and verifying that a connector instance is available to serve it.

## What you need

- Aurelion API running at `http://localhost:8000` (or set `AURELION_API_URL`)
- A connector process running and registered with the platform
- The `al` CLI installed

## Step 1: Check available connector instances

Before creating an application, confirm that a connector instance is online and note its tags. The tags on the instance must match the tags you will require on the application.

```bash
al app connectors list
```

Example output:
```
runtime-a  online  [prod, hr]  last_seen: 2026-04-23T12:00:00Z
```

If the list is empty, start a connector process first — it registers itself with the platform on startup.

## Step 2: Create the application

```bash
al app create \
  --name "Active Directory" \
  --code ad \
  --required-tags '["prod", "hr"]' \
  --config '{"base_dn": "DC=corp,DC=example,DC=com"}'
```

`--code` is the stable machine identifier. It is used by the Policy Decision Point as `target.application` and in `mapping.yaml`. Choose it carefully — it is harder to change later than `--name`.

`--required-tags` must be a subset of the tags on at least one registered connector instance, otherwise reconciliation will fail to resolve an instance.

On success:
```
id: 550e8400-e29b-41d4-a716-446655440000
name: Active Directory
code: ad
required_connector_tags: ["prod", "hr"]
is_active: true
```

## Step 3: Verify the application is listed

```bash
al app list
```

The new application should appear with `active` status.

## Step 4: Verify connector routing

Check that the platform can resolve an instance for this application. The resolution happens at runtime, but you can validate manually by confirming that at least one connector instance carries all of the application's required tags:

```bash
al app connectors list
```

If no instance has all required tags, the next reconciliation run will fail with a connector resolution error. Fix the tags on either the application (`PATCH /api/v0/applications/{id}`) or ensure the right connector instance is running.

## What's next

With the application registered, you can:

- Ingest connector results via `POST /api/v0/connector-results`
- Run reconciliation to sync access state — see [Run reconciliation](run-reconciliation.md)
