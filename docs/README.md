# `docs/`

Long-form documentation that doesn't belong in a code file.

| Subdirectory  | Purpose                                                                                          |
| ------------- | ------------------------------------------------------------------------------------------------ |
| `adr/`        | Architecture Decision Records — why we picked X over Y, with date and consequences.              |
| `runbooks/`   | On-call procedures — step-by-step playbooks for known operational scenarios.                     |

## What goes here vs. in a module's own README

| Belongs in **module README**                                | Belongs in `docs/`                              |
| ----------------------------------------------------------- | ----------------------------------------------- |
| What this module creates and how to consume it.             | Why we chose this architectural approach.       |
| The module's input variables and outputs.                   | How an on-call engineer recovers from incident. |
| Local quirks of that module's resources.                    | Cross-cutting decisions (mesh choice, region).  |

## Style

- ADRs follow the **Michael Nygard format**: Status, Context, Decision, Consequences.
- Runbooks open with a **TL;DR** ("if you only read one line"), then trigger criteria, then steps.
- Both should reference exact resource names, ARNs, console URLs, and CLI commands — not generic descriptions.
