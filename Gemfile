source 'https://rubygems.org'

gem 'veil', git: 'https://github.com/chef/chef_secrets', branch: 'main'
gem "knife-tidy", git: "https://github.com/chef/knife-tidy.git", branch: "nikhil/CHEF-12436-update-ruby-3.3"
gemspec

group :development do
  gem 'rspec'
  gem 'rake'
  gem 'fakefs'
  gem 'simplecov'
  gem "chef-zero", "~> 15" # eval when we drop ruby 2.6
  gem "chef", "~> 18"
  gem "ohai", "~> 18" # eval when we drop ruby 2.6
  gem "knife", "~> 18"
end