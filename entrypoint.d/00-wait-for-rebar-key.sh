#!/bin/bash

while [[ ! -e /etc/rebar-data/rebar-key.sh ]] ; do
  echo "Waiting for rebar-key.sh to show up"
  sleep 5
done

# Wait for the webserver to be ready.
. /etc/rebar-data/rebar-key.sh
while ! rebar ping &>/dev/null; do
  sleep 1
  . /etc/rebar-data/rebar-key.sh
done
