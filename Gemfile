source 'https://rubygems.org'

gem 'veil', git: 'https://github.com/chef/chef_secrets', branch: 'main'
gemspec

group :development do
  gem 'rspec'
  gem 'rake'
  gem 'fakefs'
  gem 'simplecov'
  gem "chef-zero", "~> 15" # eval when we drop ruby 2.6
  gem "chef", "~> 16" # eval when we drop ruby 2.6
  gem "ohai", "~> 16" # eval when we drop ruby 2.6
end