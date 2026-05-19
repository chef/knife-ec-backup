# Walk Phase — knife-ec-backup

## Purpose

This is the **Walk** phase of the Crawl → Walk → Run AI-assisted development track.
You now have system understanding from the Crawl phase. The goal is to make a
**low-risk code change** with full test coverage, demonstrating safe AI-assisted
development.

## Prerequisites

- Completed Crawl phase (SYSTEM-OVERVIEW, architecture diagram, build-test verified)
- Comfortable running `bundle exec rake spec`
- Reviewed the 3 low-risk modules in `ai-track-docs/SYSTEM-OVERVIEW.md`

## Workflow

### 1. Branch

```bash
git checkout main
git pull
git checkout -b learn/walk/<your-name>-ex<N>-<topic>
```

### 2. Choose a Task

Pick ONE from the Walk-level task list:

| Category | Example Tasks |
|----------|--------------|
| Refactor | Extract duplicated code into shared module (`ec_base.rb`) |
| Helpers  | Add utility methods (e.g., `write_json`, `ensure_dir`, `calculate_purge_list`) |
| Config   | Add/document a new CLI option or improve defaults |
| Tests    | Increase coverage on an under-tested module |
| Docs     | Add Mermaid data-flow diagrams, update architecture |

**Constraints:**
- Target only: `ec_error_handler.rb`, `tsorter.rb`, `server.rb`, or `ec_base.rb`
- Change must be < 100 lines of production code
- Must include corresponding tests

### 3. Implement with AI

Use Copilot to:
- Identify duplication or improvement opportunities
- Generate implementation code
- Generate test code

**Critical rule:** Read and understand every line before committing. Trace code
paths manually. Do not blindly accept suggestions.

### 4. Verify

```bash
# All tests pass
bundle exec rake spec

# Coverage did not decrease
cat coverage/.last_run.json

# Review diff
git diff --stat
```

### 5. Commit & PR

```bash
git add -A
git commit -s -m "refactor: extract shared helpers into ec_base"
git push origin learn/walk/<your-name>-ex<N>-<topic>
```

PR must include:
- Title: `<type>: <description>` (e.g., `refactor: extract write_json and ensure_dir into ec_base`)
- Label: `ai-assisted`
- Body: summary of prompts used, human verification performed, test results

## Suggested Prompts

Use these as starting points with Copilot:

### Discover Duplication
```
Identify duplicated code between ec_backup.rb and ec_restore.rb.
Show me the exact lines that are repeated.
```

### Plan a Refactor
```
Propose a multi-file refactor plan (2-4 files), then diffs, then tests.
```

### Generate Tests
```
Write RSpec tests for the calculate_purge_list method in ec_base.rb.
Follow the existing test patterns in spec/chef/knife/ec_base_spec.rb.
```

### Validate Architecture
```
Update architecture docs so nodes map to real repo paths; add 2-3 data
flows; validate diagram renders in CI.
```

## Evidence Checklist

Before marking your Walk PR as ready for review:

- [ ] Change targets only low-risk modules
- [ ] `bundle exec rake spec` passes (0 failures)
- [ ] Coverage >= previous value (check `.last_run.json`)
- [ ] All commits signed (`git log --show-signature`)
- [ ] PR description includes: prompts used, human review notes, test output
- [ ] No edits to `VERSION`, `CHANGELOG.md`, `.expeditor/`
- [ ] Reviewed every generated line — no blind accepts

## What Comes Next (Run Phase)

After Walk is merged, you'll move to production-level work:
- Full feature implementation or bugfix
- Integration with Jira workflow
- Complete PR lifecycle (review, CI, merge)
- Branch pattern: `learn/run/<name>-ex<N>-<topic>`

## Related Files

- `.copilot-track/crawl/README.md` — Prior phase context
- `ai-track-docs/SYSTEM-OVERVIEW.md` — Module inventory & risk levels
- `ai-track-docs/architecture.mmd` — Architecture diagram
- `ai-track-docs/build-test.md` — Build & test commands
- `CONTRIBUTING.md` — Full contribution guidelines
