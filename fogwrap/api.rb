#!/usr/bin/env ruby

require 'json'
require 'jimson' # This is a JSONRPC 2.0 service
require 'puma'
# We wrap the relevant bits of Fog to get our work done.
require 'fog'
# require 'diplomat'

class Servers
  extend Jimson::Handler
  
  def create(endpoint, args)
    ep = get_endpoint(endpoint)
    ep.servers.create(args)
  end

  def list(endpoint)
    ep = get_endpoint(endpoint)
    ep.servers
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

# Register with Diplomat
#Diplomat::Service.register(name: "fogwrap",
#                           tags: ["system"],
#                           port: 3000,
#                           check: {
#                             http: "http://localhost:3000"
#                           })
router = Jimson::Router.new
router.namespace('servers',Servers.new)
server = Jimson::Server.new(router, port: 3000, server: 'puma')
server.start
