source 'https://rubygems.org'

gem 'veil', git: 'https://github.com/chef/chef_secrets', branch: 'main'
gem "chef", git: 'https://github.com/chef/chef.git', branch: 'praj/add_frozen_info_to_metadata_chef_18'
gemspec

group :development do
  gem 'rspec'
  gem 'rake'
  gem 'fakefs'
  gem 'simplecov'
  gem "chef-zero", "~> 15" # eval when we drop ruby 2.6
  # gem "chef", "~> 18"
  gem "ohai" # eval when we drop ruby 2.6
  gem "knife"
end