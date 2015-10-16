#!/usr/bin/env ruby

require 'json'
require 'jimson' # This is a JSONRPC 2.0 service
require 'puma'

# We wrap the relevant bits of Fog to get our work done.
require 'fog'
require 'monitor'
# require 'diplomat'

ep_lock = Monitor.new

class API
  extend Jimson::Handler

  def create_server(endpoint, args)
    ep = get_endpoint(endpoint)
    ep.servers.create(args)
  end

  def list_servers(endpoint)
    ep = get_endpoint(endpoint)
    ep.servers.all
  end

  private

  def get_endpoint(ep)
    @endpoints ||= Hash.new
    ep_lock.synchronize do
      return @endpoints[ep] if @endpoints.has_key?(ep)
      res = Fog::Compute.new(ep)
      @endpoints[ep] = res
      return res
    end
  end
end

# Register with Diplomat
#Diplomat::Service.register(name: "fogwrap",
#                           tags: ["system"],
#                           port: 3000,
#                           check: {
#                             http: "http://localhost:3000"
#                           })
server = Jimson::Server.new(API.new, port: 3000, server: 'puma')
server.start
