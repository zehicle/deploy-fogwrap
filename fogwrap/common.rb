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
  case ep['provider']
  when 'AWS' then Fog::Compute.new(fix_hash(ep))
  when 'Google'
    unless ep['google_json_key']
      log("Google requires the JSON authentication token at google_json_key")
      raise "Cannot authenticate Google endpoint"
    end
    res = fix_hash(ep)
    res[:google_json_key_string] = JSON.generate(res.delete(:google_json_key))
    Fog::Compute.new(res)
  else
    log("Cannot get endpoint for #{ep['provider']}")
  end
end
