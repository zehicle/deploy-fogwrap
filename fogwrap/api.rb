#!/usr/bin/env ruby

require 'net/ssh'
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
    kp_name = "id-fogwrap-#{node_id}"
    kp_loc = File.expand_path("~/.ssh/#{kp_name}")
    if ! system("ssh-keygen -t rsa -b 1024 -N '' -f '#{kp_loc}'")
      log("Failed to generate new key #{kp_loc}")
      raise "Failed to generate key"
    end
    kp = Net::SSH::KeyFactory.load_private_key(kp_loc)
    case endpoint["provider"]
    when 'AWS'
      old_kp = ep.key_pairs.get(kp_name)
      old_kp.destroy if old_kp
      res = ep.import_key_pair(kp_name,"#{kp.ssh_type} #{[kp.public_key.to_blob].pack('m0')}")
      if res.status != 200
        log("Failed to import #{kp_name} to Amazon")
        raise "Failed to import key"
      end
      fixed_args[:key_name]=kp_name
      fixed_args[:tags] = {"rebar:node-id" => node_id.to_s}
      # Default to Centos 7 for the AMI.
      unless fixed_args[:image_id]
        log("Setting default image to an Ubuntu 14.04 based image")
        fixed_args[:flavor_id] ||= 't2.micro'
        fixed_args[:image_id] = case ep.region
                                when "us-west-1" then "ami-a88de2c8"
                                when "us-west-2" then "ami-b4a2b5d5"
                                when "us-east-1" then "ami-bb156ad1"
                                when "us-gov-west-1" then "ami-d6bbd9f5"
                                when "eu-west-1" then "ami-cd0fd6be"
                                when "eu-central-1" then "ami-bdc9dad1"
                                when "ap-southeast-1" then "ami-9e7dbafd"
                                when "ap-southeast-2" then "ami-187a247b"
                                when "ap-northeast-1" then "ami-7386a11d"
                                when "sa-east-1" then "ami-5040fb3c"
                                when "cn-north-1" then "ami-4264f87b"
                                else
                                  raise "No idea what region #{ep.region} is"
                                end
      end
      log("Region #{ep.region} -> image #{fixed_args[:image_id]}")
    when 'google'
      raise "Not functional yet."
    else
      raise "No idea how to handle #{endpoint["provider"]}"
    end
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
