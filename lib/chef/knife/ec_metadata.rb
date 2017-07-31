# Author:: Jeremy Miller (<jm@chef.io>)
# Copyright:: Copyright (c) 2017 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'ffi_yajl'

class Chef
  class Knife
    # This class exposes access to the version of Chef Server
    # and version of Knife Ec Backup used for a backup.
    class EcMetadata
      class NoMetadataFile < RuntimeError; end

      attr_accessor :data, :backup_path

      VERSION_FILE = 'VERSION'.freeze

      # Create a new metadata object for the backup
      # given backup location and version data.
      #
      # @param [String] backup_path
      #   the location of the backup directory
      # @param [Hash] data
      #   the hash of version metadata
      #
      def initialize(backup_path, data = {})
        @backup_path = backup_path
        @data = data
        data.empty? ? report : save
      end

      # Save the file to disk.
      #
      # @return [true]
      #
      def save
        ::File.open(path, 'w+') do |f|
          f.write(FFI_Yajl::Encoder.encode(to_hash, pretty: true))
        end

        true
      end

      # Load the metadata from disk.
      #
      # @return [Hash]
      #
      def report
        @data = FFI_Yajl::Parser.parse(::File.read(path), symbolize_names: true)
      rescue Errno::ENOENT
        raise NoMetadataFile, path
      end

      # The path to the VERSION file.
      #
      # @return [String]
      #
      def path
        ::File.join(@backup_path, VERSION_FILE)
      end

      # Hash representation of this metadata.
      #
      # @return [Hash]
      #
      def to_hash
        @data.dup
      end

      #
      # The JSON representation of this metadata.
      #
      # @return [String]
      #
      def to_json
        FFI_Yajl::Encoder.encode(@data, pretty: true)
      end
    end
  end
end
