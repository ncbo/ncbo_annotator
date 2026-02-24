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
  gem 'pry'
  gem 'simplecov'
  gem 'simplecov-cobertura' # for codecov.io
  gem 'ontoportal_testkit', github: 'alexskr/ontoportal_testkit', branch: 'main'
end

# NCBO gems (can be from a local dev path or from rubygems/git)
gem 'goo', github: 'ncbo/goo', branch: 'ontoportal-lirmm-development'
gem 'ontologies_linked_data', github: 'ncbo/ontologies_linked_data', branch: 'chore/ontoportal-lirmm-goo-compat'
gem 'sparql-client', github: 'ncbo/sparql-client', branch: 'ontoportal-lirmm-development'
