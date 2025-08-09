require_relative "artifact_helper"

class KnifeEcHelpTest < Minitest::Test
  include ArtifactHelper

  def test_ec_help
    assert_knife_ec_command("ec --help", /Available ec subcommands:/)
  end

  def test_ec_backup_help
    assert_knife_ec_command("ec backup --help", /knife ec backup DIRECTORY/)
  end

  def test_ec_restore_help
    assert_knife_ec_command("ec restore --help", /knife ec restore DIRECTORY/)
  end

  def test_ec_backup_no_args
    assert_knife_ec_command("ec backup", /Must specify backup directory as an argument/)
  end

  def test_ec_restore_no_args
    assert_knife_ec_command("ec restore", /Must specify backup directory as an argument/)
  end

  def test_ec_restore_with_path
    assert_knife_ec_command("ec restore ./test-path", /Webui Key \(\) does not exist/)
  end

  def test_ec_backup_with_path
    assert_knife_ec_command("ec backup ./test-path", /Your private key could not be loaded from .*webui_priv.pem/)
  end
end
