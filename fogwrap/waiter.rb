#!/usr/bin/env ruby

require 'fog'
require 'json'
require 'rest-client'
require 'diplomat'
require 'base64'
require 'tempfile'

def fix_hash(h)
  res = {}
  h.each_key do |k|
    res[k.to_sym] = h[k]
  end
  res
end

def log(line)
  STDOUT.puts(line)
  STDOUT.flush
end

loop do
  begin
    log "Finding endpoints of servers to check"
    endpoints = {}
    servers = {}
    response = RestClient.get('http://localhost:8500/v1/kv/fogwrap/create', params: {recurse: true}) rescue nil
    JSON.parse(response.body).each do |k|
      ep = fix_hash(JSON.parse(Base64.decode64(k["Value"])))
      endpoints[ep] ||= Fog::Compute.new(ep)
      fog_id = k["Key"].split("/",4)[-1]
      rebar_id = k["Key"].split("/",4)[-2]
      servers[k["Key"]] = [rebar_id, endpoints[ep].servers.get(fog_id)]
    end if response && response.code == 200
    servers.each do |key, val|
      server = val[1]
      rebar_id = val[0]
      log "Testing server #{server.id}"
      unless server.ready?
        log "Server #{server.id} not ready, skipping"
        next
      end
      unless %w(ec2-user ubuntu centos root).find do |user|
               server.username = user
               server.sshable? rescue false
             end
        log "Server #{server.id} not sshable, skipping"
        next
      end
      log "Adding rebar keys and enabling SSH in as root"
      server.ssh("sudo -- mkdir -p /root/.ssh")
      server.ssh("sudo -- sed -i -r '/(PasswordAuthentication|PermitRootLogin)/d' /etc/ssh/sshd_config")
      server.ssh("sudo -- printf '\nPasswordAuthentication %s\nPermitRootLogin %s\n' no yes >> /etc/ssh/sshd_config")
      server.ssh("sudo -- service ssh restart")
      server.ssh("sudo -- service sshd restart")
      Tempfile.open("fogwrap-keys") do |f|
        pubkeys = JSON.parse(`rebar deployments get system attrib rebar-access_keys`)
        pubkeys['value'].each_value do |v|
          f.puts(v.strip)
        end
        f.flush
        f.fsync
        server.scp(f.path,"/tmp/rebar_keys")
      end
      server.ssh("sudo -- mv /tmp/rebar_keys /root/.ssh/authorized_keys")
      server.ssh("sudo -- chmod 600 /root/.ssh/authorized_keys")
      server.ssh("sudo -- chown root:root /root/.ssh/authorized_keys")
      log("Adding node control address #{server.public_ip_address} to node #{rebar_id}")
      system("rebar nodes set #{rebar_id} attrib node-control-address to '{\"value\": \"#{server.public_ip_address}\"}'")
      log "Marking server #{server.id} alive"
      Diplomat::Kv.delete(key)
      system("rebar nodes update #{rebar_id} '{\"alive\": true, \"available\": true}'")
      log("Adding rebar-joined-node to node #{rebar_id}")
      system("rebar nodes bind #{rebar_id} to rebar-joined-node")
      log("Committing node #{rebar_id}")
      system("rebar nodes commit #{rebar_id}")
    end
  rescue Exception => e
    log "Caught error, looping"
    log "Exception: #{e.message}"
    log e.backtrace
  end
  sleep 10
end
