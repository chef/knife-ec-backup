# Build & Test Guide — knife-ec-backup

## Prerequisites

- Ruby >= 3.1 (via rbenv/asdf)
- Bundler
- PostgreSQL client libraries (for `pg` gem compilation)
- Git

## Setup

```bash
# Install Ruby dependencies
bundle install

# Verify installation
bundle exec knife ec backup --help
```

## Running Tests

```bash
# Run all unit specs (excludes smoke tests)
bundle exec rake spec

# Run a specific spec file
bundle exec rspec spec/chef/knife/ec_backup_spec.rb

# Run with verbose output
bundle exec rspec --format documentation spec/

# Run only tests matching a pattern
bundle exec rspec -e "for_each_user"
```

## Test Coverage

SimpleCov generates coverage reports automatically:
```bash
bundle exec rake spec
open coverage/index.html
```

## Linting

No RuboCop config exists in-repo. Follow existing code style conventions.

## Building the Habitat Package

```bash
# Enter Habitat studio
hab studio enter

# Build
build

# Result: results/<name>.hart
```

## Building the Gem

```bash
gem build knife-ec-backup.gemspec
# Output: knife-ec-backup-3.0.8.gem
```

## Common Issues

| Problem | Solution |
|---------|----------|
| `pg` gem fails to compile | Install PostgreSQL dev headers: `brew install libpq` or `apt install libpq-dev` |
| `veil` gem not found | It's a git dependency — ensure `bundle install` completes successfully |
| Specs fail with "ChefFS not found" | Ensure `chef ~> 18` gem is installed via bundle |

## CI/CD

- **Expeditor** manages automated version bumps and releases
- **Buildkite** runs specs and Habitat builds on PR
- Do NOT manually edit `VERSION` or `CHANGELOG.md` (auto-managed)
