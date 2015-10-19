#!/bin/bash

mkdir -p "$HOME/.ssh"
ssh-keygen -q -t rsa -b 1024 -N '' -f "$HOME/.ssh/fog_rsa"
