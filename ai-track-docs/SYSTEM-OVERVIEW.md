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
| **EcErrorHandler** | `lib/chef/knife/ec_error_handler.rb` | Side-effect only (logging). Thread-safe. No data-path impact. Own spec. |
| **Tsorter** | `lib/chef/tsorter.rb` | 22-line TSort wrapper. Used only in restore/import group ordering. Own spec. |
| **Server** | `lib/chef/server.rb` | Read-only version detection. Clear version boundaries. Well-tested. |

These are highlighted in green in `architecture.mmd`.

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
