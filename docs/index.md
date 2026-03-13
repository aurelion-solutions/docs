# Aurelion — Overview

Aurelion is a foundational identity and access platform designed to support the construction of enterprise-grade, deeply customized security and governance solutions.

It is not a single product.  
It is an **identity fabric** — a system that provides the underlying data, control, and execution layers upon which multiple products can be built.

---

## Architectural Positioning

Aurelion is structured into three logical layers.

### 1. Platform Layer — Core Infrastructure

The platform provides:

- Event-driven architecture (MQ-based)
- Deterministic processing pipelines
- Audit-grade event streams
- Extensible integration model (connectors)

This layer ensures resilience under load, horizontal scalability, and full traceability of every operation. All state transitions are observable and reconstructable.

### 2. Inventory Layer — Identity Data Plane

The source of truth for identity and access:

- Subjects (humans, service accounts, NHI)
- Accounts
- AccessFacts (universal access model)
- Effective access (EAS)
- Ownership and lineage

Key properties: normalized access model across systems, time-aware state (what existed at any point in time), deterministic projections, complete explainability ("who has what and why").

This layer abstracts away connector-specific complexity and creates a stable foundation for analytics and control.

### 3. Product Layer — Composable

On top of Platform + Inventory, Aurelion enables building:

- **IGA** — Identity Governance & Administration
- **IDP** — Identity Provider
- **ITDR** — Identity Threat Detection & Response
- **NHI security**
- **CIAM**
- Custom enterprise solutions

Products can be used out-of-the-box, extended, or fully replaced with custom implementations. This makes Aurelion suitable both as a ready-to-use platform and as a framework for building proprietary identity solutions.

---

## Core Principles

### Determinism First

All critical logic — access resolution, SoD, analytics — is deterministic, reproducible, and auditable.

AI is used only for interpretation and presentation, never for core decisions.

### Event-Driven by Design

All operations emit structured events. State changes are traceable via event streams. Components are loosely coupled via MQ.

This enables scalability, fault isolation, and external integrations (SIEM, SOAR, PDP).

### Explainability and Auditability

Every insight produced by the system can be traced back to raw access data, transformation steps, and applied rules. No black-box decisions.

This is critical for regulatory compliance (SOX, ISO 27001, DORA), internal security reviews, and incident investigation.

### Extensibility

Aurelion is designed to be extended at every level: connectors, mappings (raw → capability), policies, analytics, product layer.

Organizations can adapt the platform to their data model, governance model, and security posture.

---

## AI Role in Aurelion

AI is integrated as a controlled layer: summarization, report generation, explanation of risks, roadmap suggestions.

It operates strictly on prepared, structured context and does not access the database directly, mutate system state, or replace deterministic logic.

---

## Reliability and Scalability

Aurelion is designed for enterprise environments:

- MQ-backed processing ensures durable pipelines
- Components are stateless where possible
- Failure in one subsystem does not cascade
- Reprocessing and replay are supported via event streams

---

## Security and Licensing

Aurelion is distributed under a source-available license (BUSL-1.1):

- Allows inspection and internal use
- Protects the integrity of the platform
- Prevents uncontrolled redistribution in competing products

This ensures transparency for customers and sustainability for the platform.

---

## Positioning

Aurelion is not "just another IGA tool."

It is a platform for building identity systems — unified across human and non-human identities, capable of modeling real-world complexity, designed for organizations that require control, flexibility, and depth.

### First Product: Aurelion Lens

The first product built on Aurelion is **Lens**: analytics, risk visibility, explainable reports. It demonstrates the power of the underlying layers while providing immediate business value.

---

## Summary

Aurelion provides a robust platform layer, a normalized identity data plane, and a foundation for building advanced identity products.

It enables organizations to move from fragmented tools to a cohesive, extensible identity fabric.
