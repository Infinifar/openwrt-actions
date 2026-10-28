#!/usr/bin/env ruby
require 'yaml'
require 'tmpdir'
require 'rbconfig'

root = File.expand_path('..', __dir__)
helper = File.join(root, 'app_config/etc/openclash/custom/openclash_ai_policy.rb')
profiles = Dir[File.join(root, 'app_config/etc/openclash/config/*Rule*.yaml')]
raise 'expected three profiles' unless profiles.size == 3
checks = 0
Dir.mktmpdir('openclash-ai-test-') do |dir|
  profiles.each_with_index do |source, index|
    original = YAML.safe_load_file(source, aliases: true)
    ai = original.fetch('proxy-groups').find { |group| group['name'] == 'AI' }
    raise "manual AI policy missing: #{source}" unless ai['type'] == 'select' && ai['empty-fallback'] == 'REJECT' && !ai.key?('include-all') && !ai.key?('filter') && !ai.key?('use')
    raise 'unexpected additional AI-US group' if original.fetch('proxy-groups').any? { |group| group['name'] == 'AI-US' }
    countries = original.fetch('proxy-groups').select { |group| %w[HK SG JP US TW UK KR IN].include?(group['name'].split.last) }
    expected_countries = File.basename(source).start_with?('Only_CN') ? 4 : 8
    raise 'unexpected country group count' unless countries.size == expected_countries
    raise 'country icon still uses the old GitHub proxy' unless countries.all? { |group| group['icon'].start_with?('https://cdn.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/') }
    expected_names = countries.map { |group| group.fetch('name') }.partition { |name| name.split.last == 'US' }.flatten
    expected_names += ['US-AI']
    raise 'AI must contain country groups plus US-AI, US first' unless ai['proxies'] == expected_names
    expected_type = File.basename(source).include?('_Manual') ? 'select' : 'url-test'
    raise 'country node-selection behavior changed' unless countries.all? { |group| group['type'] == expected_type }
    candidate = File.join(dir, "profile-#{index}.yaml")
    File.write(candidate, File.read(source))
    2.times do |iteration|
      raise 'helper failed' unless system(RbConfig.ruby, helper, candidate)
      current = YAML.safe_load_file(candidate, aliases: true)
      raise 'AI selected state persistence disabled' unless current.dig('profile', 'store-selected')
      raise 'YAML converted off to a boolean' unless current['find-process-mode'] == 'off'
      raise 'expected five QUIC guards before AI routing' unless current.fetch('rules').first(5).all? { |rule| rule.start_with?('AND,((NETWORK,UDP),(DST-PORT,443),') && rule.end_with?(',REJECT-DROP') }
      raise 'expected six built-in OpenAI safety rules after QUIC guards' unless current.fetch('rules').drop(5).first(6).all? { |rule| rule.start_with?('DOMAIN-SUFFIX,') && rule.end_with?(',AI') }
      current_ai = current.fetch('proxy-groups').find { |group| group['name'] == 'AI' }
      raise 'AI is not a manual country selector' unless current_ai['type'] == 'select' && current_ai['proxies'] == expected_names && !current_ai.key?('include-all') && !current_ai.key?('filter')
      groups = current.fetch('proxy-groups').reject { |group| group['name'] == 'AI' }
      raise 'unrelated proxy groups changed' unless groups == original.fetch('proxy-groups').reject { |group| group['name'] == 'AI' }
      %w[dns sniffer proxy-providers secret].each do |key|
        raise "unrelated field changed: #{key}" unless current[key] == original[key]
      end
      bytes = File.binread(candidate)
      if iteration.zero?
        @first = bytes
      else
        raise 'helper is not idempotent' unless bytes == @first
      end
      checks += 1
    end
  end
  legacy = YAML.safe_load_file(profiles.first, aliases: true)
  legacy_ai = legacy['proxy-groups'].find { |group| group['name'] == 'AI' }
  legacy_ai.merge!('include-all' => true, 'filter' => 'JP|SG|US', 'proxies' => ['Proxy'])
  country = legacy['proxy-groups'].find { |group| group['name'].split.last == 'US' }
  country['icon'] = 'https://ghproxy.wegod.cc/old-country.png'
  candidate = File.join(dir, 'legacy.yaml')
  File.write(candidate, YAML.dump(legacy))
  raise 'legacy migration failed' unless system(RbConfig.ruby, helper, candidate)
  migrated = YAML.safe_load_file(candidate, aliases: true)
  migrated_ai = migrated['proxy-groups'].find { |group| group['name'] == 'AI' }
  raise 'legacy AI contains leaf/provider selectors' if %w[include-all filter use].any? { |field| migrated_ai.key?(field) }
  raise 'legacy AI is not manual' unless migrated_ai['type'] == 'select' && migrated_ai['empty-fallback'] == 'REJECT'
  raise 'legacy AI choices invalid' unless migrated_ai['proxies'].size == 9 && migrated_ai['proxies'].all? { |name| name == 'US-AI' || %w[HK SG JP US TW UK KR IN].include?(name.split.last) }
  raise 'country icon override not applied' unless migrated['proxy-groups'].find { |group| group['name'].split.last == 'US' }['icon'].start_with?('https://cdn.jsdelivr.net/')
  checks += 1
  %w[url-test fallback load-balance smart].each do |kind|
    auto = YAML.safe_load_file(profiles.first, aliases: true)
    auto_ai = auto['proxy-groups'].find { |group| group['name'] == 'AI' }
    auto_ai.merge!('type' => kind, 'proxies' => ['Proxy'], 'use' => ['fixture'],
                   'url' => 'https://example.invalid/probe', 'interval' => 10,
                   'strategy' => 'round-robin', 'uselightgbm' => true, 'collectdata' => true)
    candidate = File.join(dir, "automatic-#{kind}.yaml")
    File.write(candidate, YAML.dump(auto))
    raise "#{kind} repair failed" unless system(RbConfig.ruby, helper, candidate)
    repaired = YAML.safe_load_file(candidate, aliases: true)['proxy-groups'].find { |group| group['name'] == 'AI' }
    raise "#{kind} remained automatic" unless repaired['type'] == 'select' && repaired['proxies'].size == 9
    raise "#{kind} country default changed" unless repaired['proxies'].first.split.last == 'US'
    %w[include-all filter use url interval strategy uselightgbm collectdata].each do |field|
      raise "stale automatic AI field: #{field}" if repaired.key?(field)
    end
    checks += 1
  end
  candidate = File.join(dir, 'unrelated.yaml')
  untouched = "proxy-groups: []\nrules: [MATCH,DIRECT]\n"
  File.write(candidate, untouched)
  raise 'unrelated config failed' unless system(RbConfig.ruby, helper, candidate)
  raise 'a profile without AI was modified' unless File.read(candidate) == untouched
  checks += 1
  missing = YAML.safe_load_file(profiles.first, aliases: true)
  missing['proxy-groups'].reject! { |group| %w[HK SG JP US TW UK KR IN].include?(group['name'].split.last) }
  candidate = File.join(dir, 'missing-countries.yaml')
  File.write(candidate, YAML.dump(missing))
  before = File.binread(candidate)
  raise 'missing country groups were silently accepted' if system(RbConfig.ruby, helper, candidate, err: File::NULL)
  raise 'failed migration corrupted the profile' unless File.binread(candidate) == before
  checks += 1
  absent_us = YAML.safe_load_file(profiles.last, aliases: true)
  absent_us['proxy-groups'].reject! { |group| group['name'].split.last == 'US' }
  candidate = File.join(dir, 'no-us-country.yaml')
  File.write(candidate, YAML.dump(absent_us))
  raise 'non-US-only country profile failed' unless system(RbConfig.ruby, helper, candidate)
  current = YAML.safe_load_file(candidate, aliases: true)
  choices = current['proxy-groups'].find { |group| group['name'] == 'AI' }.fetch('proxies')
  raise 'missing US country group was referenced' unless choices.size == 4 && choices.last == 'US-AI' && choices.none? { |name| name.split.last == 'US' }
  checks += 1

  %w[missing-us-ai duplicate-us-ai missing-us-group missing-proxy nonmanual-proxy].each do |kind|
    fixture = YAML.safe_load_file(profiles.first, aliases: true)
    groups = fixture.fetch('proxy-groups')
    proxy = groups.find { |group| group['name'] == 'Proxy' }
    us = groups.find { |group| group['name'].split.last == 'US' }.fetch('name')
    # Recreate the old DIRECT-first order while keeping all other valid options.
    proxy['proxies'] = (proxy['proxies'] - [us, 'US-AI']) + [us]
    proxy['proxies'] += ['US-AI', 'US-AI'] if kind == 'duplicate-us-ai'
    if kind == 'missing-us-group'
      groups.reject! { |group| group['name'] == us }
      groups.each { |group| group['proxies']&.delete(us) }
    elsif kind == 'missing-proxy'
      groups.delete(proxy)
    elsif kind == 'nonmanual-proxy'
      proxy['type'] = 'url-test'
    end
    original_proxy = Marshal.load(Marshal.dump(groups.find { |group| group['name'] == 'Proxy' }))
    original_ai = Marshal.load(Marshal.dump(groups.find { |group| group['name'] == 'AI' }))
    original_google = Marshal.load(Marshal.dump(groups.find { |group| group['name'] == 'Google' }))
    original_countries = Marshal.load(Marshal.dump(groups.select { |group| %w[HK SG JP US TW UK KR IN].include?(group['name'].split.last) }))
    candidate = File.join(dir, "proxy-#{kind}.yaml")
    File.write(candidate, YAML.dump(fixture))
    raise "Proxy migration failed: #{kind}" unless system(RbConfig.ruby, helper, candidate)
    migrated = YAML.safe_load_file(candidate, aliases: true)
    migrated_groups = migrated.fetch('proxy-groups')
    actual = migrated_groups.find { |group| group['name'] == 'Proxy' }
    if kind == 'missing-proxy' || kind == 'nonmanual-proxy'
      raise 'unowned Proxy group was created or changed' unless actual == original_proxy
    else
      expected_us = kind == 'missing-us-group' ? nil : us
      expected = ([expected_us].compact +
                  (original_proxy.fetch('proxies') - [expected_us, 'US-AI']) + ['US-AI']).uniq
      raise "Proxy options/default changed incorrectly: #{kind}" unless actual.fetch('proxies') == expected
      raise 'US-AI must occur exactly once in Proxy' unless actual.fetch('proxies').count('US-AI') == 1
      raise 'Proxy metadata changed' unless actual.reject { |key, _| key == 'proxies' } == original_proxy.reject { |key, _| key == 'proxies' }
      if expected_us
        raise 'Proxy default is not the existing US country' unless actual.fetch('proxies').first == expected_us
      else
        raise 'Proxy references a missing US country' if actual.fetch('proxies').include?(us)
      end
    end
    raise 'Proxy migration changed AI choices' unless migrated_groups.find { |group| group['name'] == 'AI' } == original_ai
    raise 'Proxy migration changed Google choices' unless migrated_groups.find { |group| group['name'] == 'Google' } == original_google
    raise 'Proxy migration changed country groups' unless migrated_groups.select { |group| %w[HK SG JP US TW UK KR IN].include?(group['name'].split.last) } == original_countries
    bytes = File.binread(candidate)
    raise 'Proxy repeat migration failed' unless system(RbConfig.ruby, helper, candidate)
    raise 'Proxy migration is not idempotent' unless File.binread(candidate) == bytes
    checks += 1
  end
end

mosdns = YAML.safe_load_file(File.join(root, 'app_config/etc/mosdns/config_custom.yaml'))
policy = mosdns.fetch('plugins').find { |plugin| plugin['tag'] == 'reject_sequence' }.fetch('args').first
raise 'HTTPS/SVCB guard must return NODATA, not NXDOMAIN' unless policy['exec'] == 'reject 0'
raise 'guard must be restricted to the two service-binding query types' unless policy['matches'].include?('qtype 64 65')
raise 'guard must be restricted by domain' unless policy['matches'].any? { |match| match.start_with?('qname domain:openai.com ') }
puts "AI policy regression tests passed: #{checks} fixture checks and scoped MosDNS NODATA guard"
