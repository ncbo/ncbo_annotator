source 'https://rubygems.org'

gem 'faraday'
gem 'ffi'
gem 'oj', '~> 3.0'
gem 'rake'
gem 'request_store'
gem 'parallel'
gem 'json-ld'
gem 'jwt'
gem 'ruby-xxHash'
gem 'activesupport'

group :test do
  gem 'minitest'
  gem 'minitest-reporters'
  gem 'ontoportal_testkit', github: 'alexskr/ontoportal_testkit', branch: 'main'
  gem 'pry'
  gem 'simplecov'
  gem 'simplecov-cobertura' # for codecov.io
end

# NCBO gems (can be from a local dev path or from rubygems/git)
gem 'goo', github: 'ncbo/goo', branch: 'development'
gem 'ontologies_linked_data', github: 'ncbo/ontologies_linked_data', branch: 'develop'
gem 'sparql-client', github: 'ncbo/sparql-client', branch: 'development'
