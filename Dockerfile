ARG RUBY_VERSION
ARG DISTRO_NAME=bullseye

FROM ruby:$RUBY_VERSION-$DISTRO_NAME

RUN apt-get update -yqq && apt-get install -yqq --no-install-recommends \
  openjdk-11-jre-headless \
  raptor2-utils \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /srv/ontoportal/ncbo_annotator
RUN mkdir -p /srv/ontoportal/bundle
COPY Gemfile* *.gemspec /srv/ontoportal/ncbo_annotator/

WORKDIR /srv/ontoportal/ncbo_annotator

RUN gem update --system
RUN gem install bundler
ENV BUNDLE_PATH=/srv/ontoportal/bundle
RUN bundle install

COPY . /srv/ontoportal/ncbo_annotator
CMD ["/bin/bash"]
