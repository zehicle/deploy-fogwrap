#!/bin/bash

while true; do
    cd /opt/fogwrap
    bundle exec ./api.rb
    echo "Fogwrap API exited, restarting."
    sleep 5
done
