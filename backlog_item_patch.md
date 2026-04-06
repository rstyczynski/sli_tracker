# Patch: Backlog Item Definition

> **Integration instruction:** copy this file to `RUPStrikesBack/rules/generic/backlog_item_definition.md` in the RUP repo and add a reference to it from `GENERAL_RULES.md` under the backlog/product owner section.

## Rule

A backlog item is a short description of something needed to improve the product. It states **what** is needed and **why it matters** — not how to build it.

## Format

```
### <ID>. <Title> (one short sentence)

<2–4 sentences: what the feature/fix is, why it is needed, and any key constraint or acceptance signal.>

Test: <one line — how to know it works.>
```

## Constraints

- No design decisions, no architecture, no implementation steps.
- No tables, no bullet lists of sub-tasks.
- Small enough that a developer can hold the whole item in their head.
- If more detail is needed it belongs in the sprint elaboration document, not the backlog.

## Source

Definition from [Scrum.org — What is a Product Backlog](https://www.scrum.org/resources/what-is-a-product-backlog):
> "An emergent, ordered list of what is needed to improve the product."
> Items are refined by "adding details, such as a description, order, and size" — not by writing designs.

## Example (good)

```
### SLI-8. Test procedure execution log and OCI log capture

The integration test script leaves no durable artifact after a run. Save the full stdout/stderr to a timestamped log file and the raw OCI JSON response to a separate file, both printed at run end.

Test: both files exist after every run and paths are printed to stdout.
```

## Example (bad — too long, contains design)

```
### SLI-11. Split emit.sh into emit_oci.sh and emit_curl.sh

**Contract (shared by both scripts):**
| Variable | Description |
| --- | --- |
| SLI_OUTCOME | required — success / failure / cancelled |
...
Pure-function helpers live in emit_common.sh sourced by both backends... emit_curl.sh constructs PUT /20200831/logs/{logId}/actions/push and signs it using OCI API-key request signing (RSA-SHA256 HMAC over canonical (request-target) date host x-content-sha256 content-type content-length)...
```
