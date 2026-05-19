# Crawl Phase — knife-ec-backup

## Purpose

This is the **Crawl** phase of the Crawl → Walk → Run AI-assisted development track.
The goal is to build foundational understanding of the codebase before making any
functional changes.

## Chain-PR Workflow

Each phase produces a single PR with evidence of learning:

| Phase | Branch Pattern | Deliverables |
|-------|---------------|--------------|
| Crawl | `learn/crawl/<name>-ex<N>-<topic>` | SYSTEM-OVERVIEW, build-test, architecture diagram |
| Walk  | `learn/walk/<name>-ex<N>-<topic>` | Low-risk code change + tests |
| Run   | `learn/run/<name>-ex<N>-<topic>` | Production feature or bugfix |

PRs chain: each phase's branch is based on the previous phase's merged branch.

## Evidence in PRs

Every PR must include:
1. **AI prompt transcript** — What prompts were used (summarized in PR description)
2. **Human review** — Developer confirms AI output was validated
3. **Test results** — `bundle exec rake spec` passes
4. **No blind merges** — Developer must understand every line before approving

## Prompt Usage Guidelines

- Use AI to **explore and understand** the codebase, not to blindly generate code
- Always **read the generated output** and verify against source files
- When AI suggests a fix, **trace the code path manually** to confirm correctness
- Record key prompts that produced useful insights in PR descriptions

## Files in This Directory

- `README.md` — This file (Crawl phase context)

## Related Docs

- `ai-track-docs/SYSTEM-OVERVIEW.md` — Full system overview
- `ai-track-docs/build-test.md` — Build and test instructions
- `ai-track-docs/architecture.mmd` — Mermaid architecture diagram
