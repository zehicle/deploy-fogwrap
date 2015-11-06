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
    case endpoint["provider"]
    when 'AWS'
      log("Creating unique key pair for #{node_id}")
      kp_name = "fogwrap-node-key-#{node_id}"
      kp = ep.key_pairs.get(kp_name)
      kp.destroy if kp
      node_kp = ep.key_pairs.create(name: kp_name)
      if node_kp.private_key.nil? || node_kp.private_key.empty?
        log("Failed to create keypair for #{node.id}")
        raise "Failed to create keypair for #{node.id}"
      end
      log("Saving #{kp_name} to disk")
      File.open(
        File.expand_path("~/.ssh/#{kp_name}.pem"),
        File::CREAT|File::TRUNC|File::RDWR,
        0600) do |f|
        f.puts(node_kp.private_key.strip)
      end
      fixed_args[:key_name]=kp_name
      fixed_args[:tags] = {"rebar:node-id" => node_id.to_s}
    else
      raise "No idea how to handle #{endpoint["provider"]}"
    end
    server = ep.servers.create(fixed_args)
    log("Created server #{server.to_json}")
    system("ssh-add ~/.ssh/#{kp_name}.pem")
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
    ep.delete_key_pair(server.tags.get('rebar:kp-name'))
    server.destroy
  end

  def register(endpoint, user, keys)
    log("Registering endpoint #{endpoint} using #{keys}")
    ep = get_endpoint(endpoint)
    case endpoint["provider"]
    when "AWS"
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
      unless sg.ip_permissions.find do |ip_permission|
               ip_permission['ipRanges'].find { |ip_range| ip_range['cidrIp'] == '0.0.0.0/0' } &&
                 ip_permission['fromPort'] == -1 &&
                 ip_permission['ipProtocol'] == 'icmp'
             end
        log "Allowing ICMP access"
        sg.authorize_port_range(-1..-1, ip_protocol: 'icmp')
      else
        log "ICMP access already enabled"
      end
               
      
    else
      raise "No idea how to handle #{endpoint["provider"]}"
    end
  end

  private

  def log(line)
    STDOUT.puts(line)
    STDOUT.flush
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
