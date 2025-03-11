ARG RUBY_VERSION=3.1
ARG DISTRO=bullseye

FROM ruby:$RUBY_VERSION-$DISTRO

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libxml2 \
    libxslt-dev \
    openjdk-11-jre-headless \
    raptor2-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Use a dedicated bundle path
ENV BUNDLE_PATH=/usr/local/bundle
ENV GEM_HOME=/usr/local/bundle
ENV PATH="$BUNDLE_PATH/bin:$PATH"

COPY Gemfile* *.gemspec ./

RUN gem update --system

#I nstall the exact Bundler version from Gemfile.lock (if it exists)
RUN if [ -f Gemfile.lock ]; then \
      BUNDLER_VERSION=$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1 | tr -d ' '); \
      gem install bundler -v "$BUNDLER_VERSION"; \
    else \
      gem install bundler; \
    fi

RUN bundle config set --local path '/usr/local/bundle'
RUN bundle config set --global no-document 'true'
RUN bundle install --jobs 4 --retry 3

COPY . ./

CMD ["bundle", "exec", "rake"]
