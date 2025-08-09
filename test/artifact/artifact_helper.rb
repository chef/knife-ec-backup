require "minitest/autorun"
require "open3"

module ArtifactHelper
  VALID_EXIT_CODES = [0, 1, 10].freeze

  def assert_knife_ec_command(command, expected_pattern)
    stdout, stderr, status = Open3.capture3("bundle exec knife #{command}")

    assert_includes VALID_EXIT_CODES, status.exitstatus, <<~MSG
      Command 'knife #{command}' exited with #{status.exitstatus}, not in #{VALID_EXIT_CODES}.
      STDOUT:
      #{stdout}
      STDERR:
      #{stderr}
    MSG

    assert_match expected_pattern, stdout + stderr, <<~MSG
      Expected output for 'knife #{command}' to match:
        #{expected_pattern.inspect}
      STDOUT:
      #{stdout}
      STDERR:
      #{stderr}
    MSG
  end
end
