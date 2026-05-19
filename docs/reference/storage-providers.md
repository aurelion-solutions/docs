# Storage Providers

The Data Lake abstraction the kernel uses for batch storage. Lake
writers (e.g. the `inventory_sync` engine, the bulk org-units ingest
path) talk to this Protocol; they do not import a concrete provider.

For the lake-first ingest model see
[Reconciliation](../concepts/reconciliation.md#lake-first-for-master-data).

## Protocol

`DataLakeStorage` defines three methods. Every provider implements them:

| Method | Signature | Notes |
|---|---|---|
| `write_batch` | `(dataset_type: str, records: Iterable[dict]) -> str` | Persist a batch of records under a dataset namespace; returns a `storage_key` the caller stores for later retrieval. |
| `read_batch` | `(storage_key: str) -> Iterable[dict]` | Read records by `storage_key`. |
| `delete_batch` | `(storage_key: str) -> None` | Remove the batch. |

`dataset_type` is the logical namespace for the batch (e.g.
`access_facts`, `org_units`). Providers may use it to partition writes
on disk or in object storage; the value is not interpreted by the
kernel beyond rejecting path-traversal characters.

## Provider selection

Providers are resolved by name through a factory. Built-in providers:

| Name | Status | Notes |
|---|---|---|
| `file` | implemented | Local JSONL batches under `.lake/`. Base path overridable via `AURELION_LAKE_PATH`. |
| `s3` | not implemented | Reserves the slot for an S3-compatible object-store backend; methods raise `NotImplementedError`. |
| `iceberg` | not implemented | Reserves the slot for an Apache Iceberg backend; methods raise `NotImplementedError`. |

Selecting an unimplemented provider does not fail at registration —
the factory hands back the instance — but every call to `write_batch`,
`read_batch`, or `delete_batch` raises `NotImplementedError`.

A request for an unknown name raises `UnsupportedProviderError` at
factory lookup time.

## Custom providers

Any class that satisfies the `DataLakeStorage` Protocol can be
registered through `data_lake_factory.register(name, factory_callable)`.
The factory expects a zero-argument callable that returns a new
instance — kernel runtimes use this to wire test doubles or alternative
backends without touching the engine code.

## File provider — `AURELION_LAKE_PATH`

`AURELION_LAKE_PATH` is the only env variable for the built-in `file`
provider. When unset it defaults to `<cwd>/.lake/`. Batches are
written as one JSON object per line under
`<base>/<dataset_type>/<batch_id>.jsonl`.

`dataset_type` containing `..`, `/`, or `\\` is rejected with
`ValueError` to prevent path traversal.

## See also

- [Data Lake](data-lake.md) — the logical schemas written to the lake.
- [Reconciliation](../concepts/reconciliation.md) — when the lake is
  on the write path.
