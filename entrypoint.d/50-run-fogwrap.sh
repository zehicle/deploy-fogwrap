#!/bin/bash

forwarder=$(cat /etc/hosts | grep forwarder | awk '{ print $1 }' | sort -u)

ip route del default
ip route add default via $forwarder

cat >> /etc/consul.d/fogwrap.json <<EOF
{
  "service": {
    "name": "fogwrap",
    "tags": [ "system" ],
    "address": "${forwarder%%/*}",
    "port": 3030
    "check": {
      "http": "http://localhost:3030",
      "interval": "10s"
    }
  }
}
EOF

run_forever() (
    while true; do
        "$@"
        sleep 5
    done
)

consul reload
cd /opt/fogwrap

run_forever bundle exec ./api.rb &
run_forever bundle exec ./waiter.rb &
run_forever sleep 300
