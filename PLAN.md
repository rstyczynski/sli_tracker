# Development plan

SLI Tracker is a set of GitHub Actions and shell scripts that track and emit Service Level Indicators (SLI) to OCI Logging from CI/CD pipelines.

Instruction for the operator: keep the development sprint by sprint by changing `Status` label from Planned via Progress to Done. To achieve simplicity each iteration contains exactly one feature. You may add more backlog Items in `BACKLOG.md` file, referencing them in this plan.

Instruction for the implementor: keep analysis, design and implementation as simple as possible to achieve goals presented as Backlog Items. Remove each not required feature sticking to the Backlog Items definitions.

## Sprint 1 - OCI CLI Setup

Status: Done
Mode: managed

Backlog Items:

* SLI-1. OCI CLI installation script for Linux

## Sprint 2 - OCI Access Configuration

Status: Progress
Mode: managed

Backlog Items:

* SLI-2. GitHub repository workflow OCI access configuration script/action
