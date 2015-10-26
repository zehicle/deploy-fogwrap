#!/usr/bin/env ruby

require 'fog'
require 'json'
require 'rest-client'
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
end

loop do
  endpoints = {}
  servers = {}
  keys = []
  begin
    response = RestClient.get('http://localhost:8500/v1/kv/fogwrap/create', params: {recurse: true})
    keys = JSON.parse(response.body) if response.code == 200
  rescue
    sleep 10
    next
  end
  log "Finding endpoints of servers to check"
  keys.each do |k|    
    ep = fix_hash(JSON.parse(Base64.decode64(k["Value"])))
    endpoints[ep] ||= Fog::Compute.new(ep)
    fog_id = k["Key"].split("/",4)[-1]
    rebar_id = k["Key"].split("/",4)[-2]
    servers[k["Key"]] = [rebar_id, endpoints[ep].servers.get(fog_id)]
  end

  servers.each do |key, val|
    server = val[1]
    rebar_id = val[0]
    unless server.ready?
      log "Server #{server.id} not ready, skipping"
      next
    end
    server.private_key_path = File.expand_path("~/.ssh/#{server.tags.get('rebar:kp-name')}.pem")
    unless %w(ec2-user ubuntu root).find do |user|
             server.username = user
             server.sshable?
           end
      log "Server #{server.id} not sshable, skipping"
      next
    end
    log "Adding rebar keys and enabling SSH in as root"
    server.ssh("sudo mkdir -p /root/.ssh")
    server.ssh("sed -i 's/^(PasswordAuthentication|PermitRootLogin)/#\1/g' /etc/ssh/sshd_config")
    server.ssh("printf '\nPermitEmptyPasswords %s\nPermitRootLogin %s\n' no yes >> /etc/ssh/sshd_config")
    server.ssh("service ssh restart")
    server.ssh("service sshd restart")
    Tempfile.open("fogwrap-keys") do |f|
      pubkeys = JSON.parse(`rebar deployments get system attrib rebar-access_keys`)
      pubkeys.each_value do |v|
        f.puts(v.strip)
      end
      server.scp(f.path,"/tmp/rebar_keys")
    end
    server.ssh("sudo mv /tmp/rebar_keys /root/.ssh/authorized_keys")
    server.ssh("sudo chmod 600 /root/.ssh/authorized_keys")
    log "Marking server #{server.id} alive"
    Diplomat::Kv.delete(key)
    system("rebar nodes update #{rebar_id} '{\"alive\": true, \"available\": true}'")
  end
  sleep 10
end
    
    
      
    
  

