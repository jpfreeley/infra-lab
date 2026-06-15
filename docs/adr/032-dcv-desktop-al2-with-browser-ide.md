# ADR-032: DCV Desktop on Amazon Linux 2 with Browser IDE

## Status

Accepted

## Context

Developers need a self-contained, browser-accessible remote development
environment with full IDE, Docker, Supabase, and AI-assisted coding. Options
evaluated:

- Local development (rejected: environment inconsistency, no GPU access)
- AWS WorkSpaces (rejected: cost, limited customization)
- EC2 + DCV with browser-based code editor

DCV AMIs are only available for Amazon Linux 2. AL2 has glibc 2.26 which
blocks modern binaries (VS Code > 1.85, Node.js > 18, Hermes Agent).

## Decision

Use DCV on Amazon Linux 2 with a dual-editor setup:

- **VS Code 1.85.2** (native on desktop) — last version compatible with
  glibc 2.26. Provides full extension support including AI extensions
  (Continue) via the DCV graphical session.
- **OpenVSCode Server** (Docker container, port 8080) — browser-accessible
  code editor for lightweight access when DCV is not needed. Webview-based
  extensions do not work here.

## Consequences

- DCV provides full Linux desktop accessible from any browser via HTTPS
- VS Code 1.85.2 is frozen at Jan 2024 — no updates, some newer extensions
  may be incompatible
- OpenVSCode Server works for basic editing but cannot run webview extensions
  (Continue, Hermes sidebars are blank/unresponsive in browser-based editors)
- Boot script auto-starts all services (Supabase, Docker Compose, DCV)
- Idle auto-stop after 30 minutes (monitors DCV + code-server connections)
- Persistent 50GB EBS volume at /data survives stop/start cycles
- If AL2023 DCV AMIs become available, migration would unlock modern VS Code
  and remove the glibc constraint

## Alternatives Considered

| Option | Why Rejected |
| --- | --- |
| code-server (codercom) | Webview extensions broken (Continue, Hermes blank) |
| OpenVSCode Server only | Same webview limitation for AI extensions |
| AL2023 base + manual DCV | No official DCV AMI; complex manual install |
| VS Code Remote-SSH from local | Breaks self-contained model (ties to local machine) |
