# Development plan

SLI Tracker is a set of GitHub Actions and shell scripts that track and emit Service Level Indicators (SLI) to OCI Logging from CI/CD pipelines.

Instruction for the operator: keep the development sprint by sprint by changing `Status` label from Planned via Progress to Done. To achieve simplicity each iteration usually contains one feature; a sprint may bundle more than one item when called out explicitly (see Sprint 3). You may add more backlog Items in `BACKLOG.md` file, referencing them in this plan.

Instruction for the implementor: keep analysis, design and implementation as simple as possible to achieve goals presented as Backlog Items. Remove each not required feature sticking to the Backlog Items definitions.

## Sprint 1 - OCI CLI Setup

Status: Done
Mode: managed

Backlog Items:

* SLI-1. OCI CLI installation script for Linux

## Sprint 2 - OCI Access Configuration

Status: Done
Mode: managed

Backlog Items:

* SLI-2. GitHub repository workflow OCI access configuration script/action

## Sprint 3 - Workflow and emit review

Status: Done
Mode: YOLO

This sprint bundles two review-focused backlog items under one milestone. Formal contract-review gates are skipped: ship working increments with minimal ceremony (short inception/analysis notes only if needed; no blocking review milestones).

Backlog Items:

* SLI-3. Review model-* workflows
* SLI-4. Review sli-event action
