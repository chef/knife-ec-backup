# Author:: Jeremy Miller (<jmiller@chef.io>)
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

class Chef
  class Knife
    # EcErrorHandler
    class EcErrorHandler
      require 'tempfile'

      def initialize
        @errors_file = Tempfile.new
        # exit handler
        at_exit { EcErrorHandler.display(@errors_file) }
      end

      def add(ex)
        msg = {
          timestamp: Time.now,
          message:    ex.message,
          backtrace:  ex.backtrace
        }
        if ex.respond_to?(:knife_ec_backup_rest_request=)
          msg.merge!(ex.knife_ec_backup_rest_request)
        end
        EcErrorHandler.lock_file(@errors_file, 'a') do |f|
          f.write("\n---------------------\n")
          f.write(Chef::JSONCompat.to_json_pretty(msg))
        end
      end

      def self.lock_file(file_name, mode)
        File.open(file_name, mode) do |f|
          begin
            f.flock File::LOCK_EX
            yield f
          ensure
            f.flock File::LOCK_UN
          end
        end
      end

      def self.display(file_name)
        puts "\nError Summary Report"
        EcErrorHandler.lock_file(file_name, 'r') do |f|
          f.each_line do |line|
            puts line
          end
        end
        ::File.delete(file_name)
      end
    end
  end
end
