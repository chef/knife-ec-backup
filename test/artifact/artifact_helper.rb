require "minitest/autorun"
require "open3"

class ArtifactTest < Minitest::Test
  # Accepts an exit code of 0 or 1 (some knife subcommands exit 1 even on help)
  def assert_knife_ec_command(command)
    stdout, stderr, status = Open3.capture3("knife #{command} --help")
    acceptable_exit_codes = [0, 1]

    assert_includes acceptable_exit_codes, status.exitstatus, <<~MSG
      Command 'knife #{command} --help' failed.
      Exit status: #{status.exitstatus}
      STDOUT:
      #{stdout}
      STDERR:
      #{stderr}
    MSG
  end
end
