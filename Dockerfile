FROM digitalrebar/base
MAINTAINER Victor Lowther <victor@rackn.com>
# COPY entrypoint.d/*.sh /usr/local/entrypoint.d/
COPY fogwrap /opt/fogwrap

RUN /usr/local/go/bin/go get -u github.com/digitalrebar/rebar-api/rebar \
  && cp "$GOPATH/bin/rebar" /usr/local/bin \
  && apt-get -y update \
  && apt-get -y install software-properties-common wget \
  && apt-add-repository ppa:brightbox/ruby-ng \
  && add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-backports main restricted universe multiverse" \
  && apt-get -y update \
  && apt-get -y install ruby2.2 ruby2.2-dev make cmake curl build-essential jq libxml2-dev libcurl4-openssl-dev libssl-dev \
  && gem install bundler \
  && mkdir -p /var/cache/fogwrap/gems \
  && (cd /opt/fogwrap && bundle install --path /var/cache/fogwrap/gems --standalone --binstubs /usr/local/bin)
