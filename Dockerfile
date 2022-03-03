FROM ruby:2.6

RUN apt-get update -yqq && apt-get install -yqq --no-install-recommends openjdk-11-jre-headless raptor2-utils
# The Gemfile Caching Trick
RUN mkdir -p /srv/ontoportal/ncbo_annotator
COPY Gemfile* /srv/ontoportal/ncbo_annotator/
WORKDIR /srv/ontoportal/ncbo_annotator
RUN gem install bundler -v "$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1)"
RUN bundle install
COPY . /srv/ontoportal/ncbo_annotator
