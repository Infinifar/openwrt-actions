#!/usr/bin/env ruby
require 'yaml'
require 'tmpdir'
require 'rbconfig'
root = File.expand_path('..', __dir__)
helper = File.join(root, 'app_config/etc/openclash/custom/openclash_docker_policy.rb')
profiles = Dir[File.join(root, 'app_config/etc/openclash/config/*Rule*.yaml')]
raise 'expected three profiles' unless profiles.size == 3
url = 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/docker.mrs'
legacy_url = 'https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Docker/Docker.yaml'
extra = 'RULE-SET,DockerHubExtra,Docker'
legacy = 'RULE-SET,Docker,Docker'
checks = 0
Dir.mktmpdir('openclash-docker-test-') do |dir|
  path = File.join(dir, 'profile.yaml')
  apply = lambda do |data, success = true|
    File.write(path, YAML.dump(data))
    File.chmod(0o600, path)
    before = File.binread(path)
    result = system(RbConfig.ruby, helper, path, err: File::NULL)
    raise 'unexpected helper exit status' unless result == success
    raise 'failed policy changed the file' if !success && File.binread(path) != before
    YAML.load_file(path, aliases: true)
  end
  profiles.each do |source|
    original = YAML.load_file(source, aliases: true)
    provider = original.fetch('rule-providers').fetch('DockerHubExtra')
    raise 'supplement format mismatch' unless provider.values_at('type', 'behavior', 'format') == %w[http domain mrs]
    raise 'supplement URL/path mismatch' unless provider['url'] == url && provider['path'] == './rule_provider/DockerHubExtra.mrs'
    raise 'legacy Docker URL mismatch' unless original.dig('rule-providers', 'Docker', 'url') == legacy_url
    rules = original.fetch('rules')
    raise 'source rule order mismatch' unless rules.index(extra) < rules.index(legacy) && rules.index(legacy) < rules.index('RULE-SET,Download,Domestic')
    current = apply.call(original)
    %w[proxy-groups proxy-providers dns sniffer secret profile].each do |key|
      raise "unrelated field changed: #{key}" unless current[key] == original[key]
    end
    raise 'unrelated providers changed' unless current['rule-providers'] == original['rule-providers']
    raise 'unexpected rule changes' unless current['rules'] == original['rules']
    first = File.binread(path)
    raise 'second application failed' unless system(RbConfig.ruby, helper, path)
    raise 'policy is not byte-idempotent' unless first == File.binread(path)
    raise 'file permissions changed' unless File.stat(path).mode & 0o777 == 0o600
    checks += 1
  end
  fixture = {
    'proxy-groups' => [{'name' => 'Docker', 'type' => 'select', 'proxies' => ['Proxy', 'DIRECT']}],
    'rule-providers' => {'Docker' => {'type' => 'http', 'url' => "https://ghproxy.wegod.cc/#{legacy_url}"}},
    'rules' => ['DOMAIN-SUFFIX,example.test,DIRECT', 'DOMAIN-SUFFIX,chatgpt.com,AI',
                'RULE-SET,Download,Domestic', legacy, extra, extra, 'MATCH,Final'],
    'dns' => {'enable' => true}, 'secret' => 'fixture-only'
  }
  fixed = apply.call(fixture)
  raise 'legacy URL not repaired' unless fixed.dig('rule-providers', 'Docker', 'url') == legacy_url
  expected = fixture['rules'].first(2) + [extra, legacy, 'RULE-SET,Download,Domestic', 'MATCH,Final']
  raise 'priority/deduplication mismatch' unless fixed['rules'] == expected
  %w[proxy-groups dns secret].each { |key| raise 'fixture field changed' unless fixed[key] == fixture[key] }
  checks += 1
  custom = Marshal.load(Marshal.dump(fixture))
  custom['rule-providers']['Docker']['url'] = 'https://example.test/my-docker.yaml'
  fixed = apply.call(custom)
  raise 'custom legacy URL overwritten' unless fixed.dig('rule-providers', 'Docker', 'url') == 'https://example.test/my-docker.yaml'
  checks += 1
  collision = Marshal.load(Marshal.dump(fixture))
  collision['rule-providers']['DockerHubExtra'] = {'url' => 'https://example.test/personal.mrs'}
  apply.call(collision, false)
  checks += 1
  target_collision = Marshal.load(Marshal.dump(fixture))
  target_collision['rules'] << 'RULE-SET,DockerHubExtra,MyCustomTarget'
  apply.call(target_collision, false)
  checks += 1
  unrelated = "# preserve comments too\nproxy-groups: []\nrules: ['MATCH,DIRECT']\n"
  File.write(path, unrelated)
  raise 'unrelated profile failed' unless system(RbConfig.ruby, helper, path)
  raise 'unrelated profile changed' unless File.binread(path) == unrelated
  checks += 1
  bare = {'proxy-groups' => fixture['proxy-groups'], 'rules' => ['DOMAIN-SUFFIX,example.test,DIRECT', 'MATCH,Final']}
  fixed = apply.call(bare)
  raise 'missing legacy provider was invented' if fixed['rule-providers'].key?('Docker')
  raise 'supplement after catch-all' unless fixed['rules'] == ['DOMAIN-SUFFIX,example.test,DIRECT', extra, 'MATCH,Final']
  checks += 1
  raise 'temporary policy files remain' unless Dir[File.join(dir, '*.docker-policy.*')].empty?
end
puts "Docker policy tests passed: #{checks} fixtures"
