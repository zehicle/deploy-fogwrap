#!/usr/bin/env ruby

require 'json'
require 'jimson' # This is a JSONRPC 2.0 service
require 'puma'
# We wrap the relevant bits of Fog to get our work done.
require 'fog'
require 'diplomat'

class Servers
  extend Jimson::Handler

  def create(endpoint, args)
    ep = get_endpoint(endpoint)
    fixed_args = fix_hash(args)
    fixed_args[:private_key_path] = File.expand_path("~/.ssh/fog_rsa")
    fixed_args[:public_key_path] = File.expand_path("~/.ssh/fog_rsa.pub")
    fixed_args[:user] = "root"
    server = ep.servers.create(fixed_args)
    Diplomat::Kv.put("fogwrap/create/#{endpoint["provider"]}/#{server.id}",endpoint.to_json)
    server
  end

  def list(endpoint)
    ep = get_endpoint(endpoint)
    ep.servers
  end

  def get(endpoint, id)
    ep = get_endpoint(endpoint)
    ep.servers.get(id)
  end

  def delete(endpoint,id)
    ep = get_endpoint(endpoint)
    server = ep.servers.get(id)
    server.destroy
  end

  private
  def fix_hash(h)
    res = {}
    h.each_key do |k|
      res[k.to_sym] = h[k]
    end
    res
  end

  def get_endpoint(ep)
    Fog::Compute.new(fix_hash(ep))
  end
end

# Fire it up, boys
router = Jimson::Router.new
router.namespace('servers',Servers.new)
server = Jimson::Server.new(router, port: 3030, server: 'puma')
server.start
