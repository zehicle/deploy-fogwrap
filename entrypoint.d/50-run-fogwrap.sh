#!/bin/bash
if [[ $forwarder ]] ; then
    ip route del default
    ip route add default via $forwarder
fi

cat >> /etc/consul.d/fogwrap.json <<EOF
{
  "service": {
    "name": "fogwrap",
    "tags": [ "deployment:system" ],
    "port": 3030,
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

run_forever bundle exec ./api.rb >api.log &
run_forever bundle exec ./waiter.rb >waiter.log &
tail -f api.log waiter.log
