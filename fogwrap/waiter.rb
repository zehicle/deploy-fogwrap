#!/usr/bin/env ruby

require 'fog'
require 'json'
require 'diplomat'

def fix_hash(h)
  res = {}
  h.each_key do |k|
    res[k.to_sym] = h[k]
  end
  res
end

loop do
  attr = JSON.parse(`rebar deployments get system attrib rebar-access_keys`)
  File.open("/tmp/access_keys","w") do |f|
    attr["value"].values.each do |v|
      f.puts(v.strip)
    end
    f.puts(File.read("~/.ssh/fog_rsa.pub").strip)
  end
  
  endpoints = {}
  servers = {}
  keys = Diplomat::Kv.get('fogwrap/create', recurse: true)
  keys.each do |k|
    ep = fix_hash(JSON.parse(k[:value]))
    endpoints[ep] ||= Fog::Compute.new(ep)
    id = k[:key].split("/",4)[-1]
    servers[k[:key]] << endpoints[ep].servers.get(id)
  end
  servers.each do |key, server|
    next unless server.ready? && server.sshable?
    Diplomat::Kv.delete(key)
    server.scp("/tmp/access_keys","/root/.ssh/authorized_keys")
    system("rebar nodes update #{server.name} '{\"alive\": true, \"available\": true}'")
  end
  sleep 10
end
    
    
      
    
  

