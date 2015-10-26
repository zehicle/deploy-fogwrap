#!/usr/bin/env ruby

require 'json'
require 'jimson' # This is a JSONRPC 2.0 service
require 'puma'
# We wrap the relevant bits of Fog to get our work done.
require 'fog'
require 'diplomat'

class Servers
  extend Jimson::Handler

  def create(endpoint, node_id, args)
    log("Creating node #{node_id}")
    ep = get_endpoint(endpoint)
    fixed_args = fix_hash(args)
    fixed_args[:private_key_path] = File.expand_path("~/.ssh/fog_rsa")
    fixed_args[:public_key_path] = File.expand_path("~/.ssh/fog_rsa.pub")
    fixed_args[:user] = "root"
    server = ep.servers.create(fixed_args)
    log("Created server #{server.to_json}")
    Diplomat::Kv.put("fogwrap/create/#{node_id}/#{server.id}",endpoint.to_json)
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

  def reboot(endpoint, id)
    log("Rebooting server #{id}")
    get(endpoint,id).reboot
  end

  def delete(endpoint,id)
    log("Deleting server #{id}")
    ep = get_endpoint(endpoint)
    server = ep.servers.get(id)
    server.destroy
  end

  def register(endpoint, user, keys)
    log("Registering endpoint #{endpoint} using #{keys}")
    ep = get_endpoint(endpoint)
    keys["fogwrap"] = File.read(File.expand_path("~/.ssh/fog_rsa.pub")).strip
    case endpoint["provider"]
    when "AWS"
      keys.each do |k,v|
        next if ep.key_pairs.get(k)
        log "Registering key #{k}: #{v}"
        res = ep.import_key_pair(k,v)
        if res.body['keyFingerprint'] && !res.body['keyFingerprint'].empty?
          log "Key #{k} registered as #{res.body['keyFingerprint']}"
        else
          log "Registration of #{k} failed"
        end
      end
      sg = ep.security_groups.get('default')
      # make sure port 22 is open in the first security group
      unless sg.ip_permissions.find do |ip_permission|
               ip_permission['ipRanges'].find { |ip_range| ip_range['cidrIp'] == '0.0.0.0/0' } &&
                 ip_permission['fromPort'] == 22 &&
                 ip_permission['ipProtocol'] == 'tcp' &&
                 ip_permission['toPort'] == 22
             end
        log "Allowing SSH access"
        sg.authorize_port_range(22..22)
      else
        log "SSH access already enabled"
      end
      
    else
      raise "No idea how to handle #{endpoint["provider"]}"
    end
  end

  private

  def log(line)
    STDOUT.puts(line)
  end
                
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
