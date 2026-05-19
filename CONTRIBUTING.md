# Contributing to knife-ec-backup

## Upstream Guide

For general Chef contribution guidelines, see:
https://github.com/chef/chef/blob/main/CONTRIBUTING.md

## AI-Assisted Development Track

This repository uses a **Crawl → Walk → Run** progression for onboarding with
AI-assisted development tools (GitHub Copilot).

| Phase | Branch Pattern | Goal |
|-------|---------------|------|
| Crawl | `learn/crawl/<name>-ex<N>-<topic>` | Build system understanding; produce docs & diagrams |
| Walk  | `learn/walk/<name>-ex<N>-<topic>` | Low-risk code change with tests (refactor, helpers, config) |
| Run   | `learn/run/<name>-ex<N>-<topic>` | Production feature or bugfix with full PR workflow |

Each phase produces a PR with evidence of AI interaction and human review.

## Development Setup

```bash
bundle install
bundle exec rake spec        # Run all specs (excludes smoke)
open coverage/index.html     # View coverage report
```

## Contribution Checklist

- [ ] Branch from `main` (or chain from prior phase branch)
- [ ] All specs pass: `bundle exec rake spec`
- [ ] Coverage does not decrease (check `coverage/.last_run.json`)
- [ ] Commits are signed: `git commit -s`
- [ ] PR title follows `<type>: <JIRA-ID> - <description>` format
- [ ] Do NOT edit `VERSION`, `CHANGELOG.md`, or `.expeditor/` (auto-managed)
- [ ] AI-assisted PRs carry the `ai-assisted` label

## Walk Phase Requirements

The Walk phase is the first time you make **code changes**. Requirements:

1. Target only low-risk modules (see `ai-track-docs/SYSTEM-OVERVIEW.md` → "3 Low-Risk Modules")
2. Keep changes small and reversible (refactors, extracted helpers, config tweaks)
3. Write or expand unit tests for every change
4. Include the onboarding prompt file (`.copilot-track/walk/`) in your PR
5. Document which AI prompts were used and what human verification was performed

## Key Files

| File | Purpose |
|------|---------|
| `.copilot-track/crawl/README.md` | Crawl phase instructions |
| `.copilot-track/walk/README.md` | Walk phase instructions |
| `ai-track-docs/` | Architecture docs, build guide, flow diagrams |
| `.github/copilot-instructions.md` | Copilot context for this repo |

