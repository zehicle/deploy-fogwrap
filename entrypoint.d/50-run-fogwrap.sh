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

consul reload

while true; do
    cd /opt/fogwrap
    bundle exec ./api.rb
    echo "Fogwrap API exited, restarting."
    sleep 5
done
