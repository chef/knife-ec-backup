# PR Coverage Snippet Template
#
# After running `bundle exec rake spec`, SimpleCov outputs coverage to:
#   - coverage/index.html        (human-readable report)
#   - coverage/.last_run.json    (machine-readable last-run summary)
#   - coverage/coverage.json     (full JSON, CI only — when ENV['CI'] is set)
#
# Use the snippet below in your PR description to report coverage.
# Replace {{COVERAGE_PCT}} with the value from coverage/.last_run.json
# (field: result.line).
#
# -------------------------------------------------------------------
# Copy everything between the --- markers into your PR body:
# -------------------------------------------------------------------
#
# ## Test Coverage
#
# | Metric       | Value             |
# |--------------|-------------------|
# | Line Coverage | **{{COVERAGE_PCT}}%** |
# | Threshold     | 60%               |
# | Report        | `coverage/index.html` |
#
# -------------------------------------------------------------------
#
# To extract the percentage automatically in CI or locally:
#
#   ruby -rjson -e 'puts JSON.parse(File.read("coverage/.last_run.json"))["result"]["line"]'
#
# Or with jq:
#
#   jq '.result.line' coverage/.last_run.json
#
