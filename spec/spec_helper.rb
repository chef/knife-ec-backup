$:.push File.join(File.dirname(__FILE__), '..', 'lib')
require 'simplecov'
SimpleCov.start do
   add_filter "/spec/"
   add_filter "/vendor/"

   # Emit coverage/coverage.json for CI consumption
   if ENV['CI']
     require 'simplecov_json_formatter'
     formatter SimpleCov::Formatter::MultiFormatter.new([
       SimpleCov::Formatter::HTMLFormatter,
       SimpleCov::Formatter::JSONFormatter
     ])
   end

   # In CI, coverage is reported in the job summary but does NOT block merges.
   # Locally, warn (but still exit 0) if coverage drops below threshold.
   minimum_coverage(ENV['CI'] ? 0 : 60)
end
