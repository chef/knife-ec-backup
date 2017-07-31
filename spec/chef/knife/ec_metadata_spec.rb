require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spec_helper'))
require 'chef/knife/ec_metadata'
require 'fakefs/spec_helpers'

describe Chef::Knife::EcMetadata do
  include FakeFS::SpecHelpers

  let (:beep_path) { '/beep' }
  let (:boop) { { beep: '3.2.1', boop: '1.2.3' } }
  let (:mock_content) { <<-EOF
{
  "beep": "3.2.1",
  "boop": "1.2.3"
}
EOF
}

  before(:each) do
    FileUtils.mkdir_p(beep_path)
    @ec_backup  = Chef::Knife::EcMetadata.new(beep_path, boop)
    @ec_restore = Chef::Knife::EcMetadata.new(beep_path)
  end

  describe '#initialize' do
    context 'when a backup directory path and version attribute hash is supplied' do
      it 'accepts both' do
        expect(@ec_backup.backup_path).to eq(beep_path)
        expect(@ec_backup.data).to eq(boop)
      end
    end

    context 'when only a backup directory path is specified' do
      it 'accepts one' do
        expect(@ec_restore.backup_path).to eq(beep_path)
        expect(@ec_restore.data).to eq({})
      end
    end
  end

  describe '#store' do
    it 'correctly saves the metadata information to disk' do
      @ec_backup.store
      expect(::File.read(::File.join(beep_path, 'VERSION'))).to match mock_content
    end
  end

  describe '#load' do
    it 'correctly parses VERSION file contents' do
      @ec_backup.store
      expect(@ec_restore.load).to eq(boop)
    end
  end

  describe '#path' do
    it 'returns a string of the backup path' do
      expect(@ec_backup.path).to eq(::File.join(beep_path, 'VERSION'))
    end
  end

  describe '#to_hash' do
    it 'returns the data instance variable hash' do
      expect(@ec_backup.to_hash).to eq(@ec_backup.data)
    end
  end

  describe '#to_json' do
    it 'returns the data instance variable in json' do
      expect(@ec_backup.to_json).to match mock_content
    end
  end
end
