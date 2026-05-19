# knife-ec-backup System Overview

## Summary

**knife-ec-backup** (v3.0.8) is a Ruby gem extending the Chef `knife` CLI with subcommands
for full backup/restore of Chef Infra Server data. Packaged via Habitat for production
deployment on Chef Automate instances.

---

## Language & Runtime

| Aspect | Detail |
|--------|--------|
| Language | Ruby (100%) |
| Required Ruby | >= 3.1 |
| Framework | Chef Knife plugin (Thor-style CLI DSL) |
| Packaging | RubyGem + Habitat `.hart` package |
| Test Framework | RSpec + SimpleCov + FakeFS |
| CI/CD | Expeditor + Buildkite |

---

## Entry Points

| Entry | Path | Context |
|-------|------|---------|
| CLI (production) | `bin/knife` | Habitat: `hab pkg exec chef/knife-ec-backup knife ec ...` |
| Subcommand discovery | `lib/chef/knife/ec_*.rb` | Auto-registered by Chef Knife |
| Tests | `bundle exec rake spec` | RSpec, excludes smoke |
| Artifact test | `test/artifact/` | Smoke tests for Habitat package |

---

## Module Inventory

### Commands (lib/chef/knife/)
| File | Command | Role |
|------|---------|------|
| `ec_backup.rb` | `knife ec backup` | Download all server data to disk |
| `ec_restore.rb` | `knife ec restore` | Upload backup to a server |
| `ec_import.rb` | `knife ec import` | Import into pre-existing orgs (multi-tenant) |
| `ec_key_export.rb` | `knife ec key export` | Export users/keys via PostgreSQL |
| `ec_key_import.rb` | `knife ec key import` | Import users/keys via PostgreSQL |

### Shared Modules (lib/chef/)
| File | Role |
|------|------|
| `knife/ec_base.rb` | Shared CLI options, config, auth, REST clients |
| `knife/ec_key_base.rb` | SQL connection, Sequel ORM, config loading |
| `knife/ec_error_handler.rb` | Thread-safe error logging to JSON |
| `server.rb` | Version detection, feature flags |
| `automate.rb` | Automate path detection |
| `tsorter.rb` | Topological sort for group dependencies |
| `org_id_cache.rb` | Org GUID lookup cache (SQL) |

---

## Key Dependencies

| Gem | Purpose |
|-----|---------|
| `chef ~> 18.0` | Knife framework, ChefFS parallel I/O, ServerAPI |
| `sequel ~> 5.9` | PostgreSQL access for key/user tables |
| `pg` | Native PostgreSQL driver |
| `veil` | Secrets management (webui_key, passwords) |
| `knife-tidy` | Backup data cleanup companion |
| `concurrent-ruby` | Thread pool (via chef-utils `parallel_map`) |

---

## Concurrency Model

ChefFS `copy_to` drives all parallel I/O:
- Uses `Concurrent::ThreadPoolExecutor` (default 10 threads)
- Configurable via `--concurrency N` → sets pool size to N-1
- `fallback_policy: :caller_runs` prevents deadlock on recursive calls
- Even `--concurrency 1` still allows recursive parallelism within ChefFS

---

## Data Flow (Backup)

```
knife ec backup <dir>
  ├── Users: REST GET /users → users/*.json
  ├── User ACLs: REST GET users/<name>/_acl → user_acls/*.json
  ├── SQL Export (optional): Sequel → key_dump.json, key_table_dump.json
  └── Per organization:
       ├── org.json, members.json, invitations.json (REST)
       └── ChefFS copy_to (parallel):
            cookbooks, environments, roles, nodes,
            data_bags, clients, groups, containers, acls
```

---

## 3 Low-Risk Modules (Safe to Modify)

| Module | File | Why Safe |
|--------|------|----------|
| **EcErrorHandler** | `lib/chef/knife/ec_error_handler.rb` | Side-effect only (logging). Thread-safe. No data-path impact. Own spec at `spec/chef/knife/ec_error_handler_spec.rb`. Now includes `TRANSIENT_ERRORS` classification, `error_count` tracking, `has_errors?`, `transient_error?(ex)`, consistent `at_exit` exit-status enforcement, and `suppress_exit:` option for testability. |
| **Tsorter** | `lib/chef/tsorter.rb` | 22-line TSort wrapper. Used only in restore/import group ordering. Own spec at `spec/chef/tsorter_spec.rb`. |
| **Server** | `lib/chef/server.rb` | Read-only version detection. Clear version boundaries. Own spec at `spec/chef/server_spec.rb`. |

These are highlighted in green in `architecture.mmd`.

---

## Recent Changes (CHEF-29855 Fixes)

### Files Modified

| File | Change |
|------|--------|
| `lib/chef/knife/ec_error_handler.rb` | Added `TRANSIENT_ERRORS`, `error_count`, `has_errors?`, `transient_error?`, `at_exit` exit-status enforcement, `suppress_exit:` option |
| `lib/chef/knife/ec_base.rb` | Added `require 'digest'` guard for Ruby >= 3.2 (prevents `Digest::Base cannot be directly inherited`) |
| `lib/chef/knife/ec_backup.rb` | Expanded `chef_fs_copy_pattern` rescue to include `Net::HTTPFatalError`, `Errno::ECONNRESET`, `ECONNREFUSED`, `ETIMEDOUT` |
| `lib/chef/knife/ec_restore.rb` | Same rescue expansion as backup |
| `lib/chef/knife/ec_import.rb` | Same rescue expansion as backup |
| `spec/chef/knife/ec_error_handler_spec.rb` | Comprehensive tests (22 examples) covering all new behavior |

### Assumptions & Verification

| Assumption | How to Verify |
|------------|---------------|
| `Net::HTTPServerException` is the class raised for 4xx/5xx in knife's Ruby version (3.1) | `ruby -e "require 'net/http'; p Net::HTTPServerException"` — exists in Ruby 3.1, deprecated in 3.2+ |
| `Net::HTTPFatalError` covers 5xx specifically in newer Net::HTTP | Check `net/http/exceptions.rb` in Ruby stdlib |
| ChefFS `copy_to` uses threads (not forks), so `at_exit` fires once per process | Verified by testing — single process model |
| The `at_exit` hook ordering (last registered runs first) means each handler instance has its own check | Multiple handlers in tests confirmed this with `suppress_exit:` |
| `Errno::ECONNRESET` is the actual class for "Connection reset by peer" on Linux/macOS | `ruby -e "raise Errno::ECONNRESET" 2>&1` confirms message |

---

## Production Usage

```bash
# On Chef Automate server (Habitat)
sudo hab pkg exec chef/knife-ec-backup knife ec backup /backup/$(date +%Y%m%d) \
  --webui-key /hab/svc/automate-cs-oc-erchef/data/webui_priv.pem \
  -s https://<automate-url>/ \
  -c /hab/svc/automate-cs-nginx/config/knife_superuser.rb \
  --concurrency 5

# From remote workstation
knife ec backup ./backup \
  --webui-key webui_priv.pem \
  -s https://<automate-url>/ \
  -c knife_superuser.rb \
  --concurrency 1
```
