FROM k8s.gcr.io/pause:3.1 AS pause

FROM ruby:3.2-bullseye

ENV USER=lexicon
ENV UID=1000
ENV GID=1000

COPY --from=pause /pause /pause

RUN mkdir /lexicon && \
    addgroup --gid "$GID" "$USER" && \
    adduser \
        --disabled-password \
        --gecos "" \
        --home /lexicon \
        --ingroup "$USER" \
        --no-create-home \
        --uid "$UID" \
        "$USER" && \
    apt-get update && \
    apt-get -y install postgis postgresql-client postgresql-contrib libpq-dev p7zip-full pigz libyajl-dev --no-install-recommends && \
    apt-get -y install python3-setuptools python3-dev python3-pip --no-install-recommends

WORKDIR /lexicon

ADD requirements.txt /lexicon/
RUN pip3 install wheel
RUN pip3 install -r requirements.txt

ENV BUNDLE_PATH=/lexicon/vendor/bundle \
    BUNDLER_VERSION='2.2.33'
RUN gem install bundler -v $BUNDLER_VERSION
COPY Gemfile Gemfile.lock /lexicon/
RUN bundle install --jobs $(nproc) --path vendor/bundle

ADD . /lexicon/
RUN chown -R lexicon:lexicon /lexicon

RUN sha1sum Dockerfile docker-compose-dev.yml Gemfile requirements.txt lexicon > build_hash.sha1

USER lexicon

CMD ["/pause"]
