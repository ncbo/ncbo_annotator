#!/bin/bash
# sample script for running unit tests in docker.  This functionality should be moved to a rake task
#
# add config for unit testing
[ -f config/config.rb ] || cp config/config.test.rb config/config.rb
docker-compose build
#docker-compose up --exit-code-from unit-test

docker-compose run --rm ruby bundle exec rake test TESTOPTS='-v'
#docker-compose down
docker-compose kill
