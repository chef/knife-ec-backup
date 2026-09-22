# Author:: Jeremy Miller (<jmiller@chef.io>)
# Copyright:: Copyright (c) 2013-2025 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.
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
    # This class handles the errors that we might encounter on a
    # backup or restore, it stors the errors inside a specific file
    # inside the working directory.
    class EcErrorHandler

      attr_reader :err_file

      # Creates a new instance of the EcErrorHandler to start
      # adding errors during a backup or restore.
      def initialize(working_dir, process)
        @err_dir = "#{working_dir}/errors"
        FileUtils.mkdir_p(@err_dir)
        @error_count = 0
        @process = process

        # Create an specific error file name depending
        # of where the process comes from.
        @err_file = if process == Chef::Knife::EcRestore
                      File.join(@err_dir, "restore-#{Time.now.iso8601}.json")
                    elsif process == Chef::Knife::EcBackup
                      File.join(@err_dir, "backup-#{Time.now.iso8601}.json")
                    else
                      File.join(@err_dir, "other-#{Time.now.iso8601}.json")
                    end

        # exit handler
        at_exit do
          display(@err_file)
          override_exit_status
        end
      end

      # Forces a consistent, non-zero exit status when errors were recorded so
      # that a run with a high-verbosity flag (e.g. -VVV) and one without it
      # report the same status. Only applies to `knife ec import`; other
      # commands keep their original exit status. Skipped under RSpec so the
      # test suite's own exit status is not altered.
      def override_exit_status
        return if defined?(RSpec)
        return unless @process == Chef::Knife::EcImport

        status = consistent_exit_status($!)
        exit(status) unless status.nil?
      end

      # Decides the process exit status so it is identical regardless of
      # verbosity. Under -VVV knife re-raises and Ruby exits 1; without it knife
      # rescues and exits with a different code (e.g. 100). Both are error cases
      # and must agree.
      #
      # +error+ is the exception propagating at exit (Ruby's $!). Returns the
      # status to force, or nil to leave the current status untouched.
      def consistent_exit_status(error = $!)
        case error
        when SystemExit
          # Normalize any non-zero exit (e.g. knife's exit 100) to 1.
          return 1 unless error.success?
          has_errors? ? 1 : nil
        when nil
          # Normal termination: exit 1 only if errors were logged.
          has_errors? ? 1 : nil
        else
          # A raw exception is propagating (typically under -VVV); Ruby already
          # exits 1 and prints the backtrace, so leave it untouched.
          nil
        end
      end

      # Returns true when any error has been recorded.
      def has_errors?
        @error_count > 0
      end

      # Add an exception to the error file.
      #
      # For now we are writing all the errors to a single file, but
      # in the future we would like to be able to generate a full path
      # just as we do when we are backing up the Server, just that putting
      # the file inside `{work_dir}/errors/{path}`
      #
      # Example:
      # A failed user
      # => {work_dir}/errors/users/afiune.json
      # A failed cookbook
      # => {work_dir}/errors/cookbooks/burger.json
      # A failed environment
      # => {work_dir}/errors/environment/dev.json
      #
      # The advantages of this schema is the ability to retry the backup or
      # restore and pick up where we left.
      def add(ex)
        @error_count += 1
        msg = {
          timestamp:  Time.now,
          message:    ex.message,
          backtrace:  ex.backtrace,
          exception:  ex.class
        }

        if ex.respond_to?(:chef_rest_request=) && ex.chef_rest_request
          msg.merge!(
            req_path: ex.chef_rest_request.path,
            req_method: ex.chef_rest_request.method
          )
        elsif ex.instance_of?(Chef::ChefFS::FileSystem::NotFoundError)
          msg.merge!(
            entry: ex.entry,
            cause: ex.cause,
            reason: ex.reason
          )
        elsif ex.instance_of?(Chef::ChefFS::FileSystem::OperationFailedError)
          msg.merge!(
            entry: ex.entry,
            operation: ex.operation
          )
        end

        lock_file(@err_file, 'a') do |f|
          f.write(Chef::JSONCompat.to_json_pretty(msg))
        end
      end

      # Why lock the error file?
      #
      # Well because ec-backup has a concurrency options that
      # will allow you to backup and restore things in parallel,
      # therefor we need to ensure that only one process is
      # writing to the error file.
      def lock_file(file_name, mode)
        File.open(file_name, mode) do |f|
          begin
            f.flock ::File::LOCK_EX
            yield f
          ensure
            f.flock ::File::LOCK_UN
          end
        end
      end

      def display(file_name = @err_file)
        # Print summary report only if error file exist
        return unless File.exist?(file_name)

        puts "\nError Summary Report"
        lock_file(file_name, 'r') do |f|
          f.each_line do |line|
            puts line
          end
        end
        puts "\nError(s) Summary file located at: '#{file_name}'"
      end
    end
  end
end
