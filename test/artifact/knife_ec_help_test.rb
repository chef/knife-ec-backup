require_relative "artifact_helper"

class KnifeEcHelpTest < ArtifactTest
  def test_ec_help
    assert_knife_ec_command("ec")
  end

  def test_ec_backup_help
    assert_knife_ec_command("ec backup")
  end

  def test_ec_restore_help
    assert_knife_ec_command("ec restore")
  end
end