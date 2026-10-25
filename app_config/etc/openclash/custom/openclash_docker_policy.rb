#!/usr/bin/env ruby
# Scoped to profiles that already provide a Docker strategy; no credentials.
require 'yaml'
path = ARGV.fetch(0)
config = YAML.safe_load_file(path, aliases: true)
exit 0 unless Array(config['proxy-groups']).any? { |group| group['name'] == 'Docker' }

name = 'DockerHubExtra'
url = 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/docker.mrs'
providers = config['rule-providers'] ||= {}
existing = providers[name]
if existing && (!existing.is_a?(Hash) || existing['url'] != url)
  abort 'Docker policy: DockerHubExtra conflicts with a custom rule provider; not overwriting it.'
end
extra_rule = "RULE-SET,#{name},Docker"
rules = Array(config['rules'])
if rules.any? { |rule| rule.to_s.start_with?("RULE-SET,#{name},") && rule != extra_rule }
  abort 'Docker policy: DockerHubExtra has a custom target; not overwriting it.'
end
providers[name] = (existing || {}).merge(
  'type' => 'http', 'behavior' => 'domain', 'format' => 'mrs',
  'url' => url, 'path' => './rule_provider/DockerHubExtra.mrs', 'interval' => 43_200
)
legacy_url = 'https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Docker/Docker.yaml'
legacy = providers['Docker']
if legacy.is_a?(Hash) && [legacy_url, "https://ghproxy.wegod.cc/#{legacy_url}"].include?(legacy['url'])
  legacy['url'] = legacy_url
end

# Reposition only our two exact Docker routes. Keep all unrelated rules in
# their existing order, including user direct overrides and AI safety rules.
legacy_rule = 'RULE-SET,Docker,Docker'
docker_rules = [extra_rule]
docker_rules << legacy_rule if rules.include?(legacy_rule)
anchor = rules.index do |rule|
  rule == legacy_rule || rule == extra_rule ||
    rule.to_s.start_with?('RULE-SET,Download,', 'MATCH,', 'FINAL,')
end || rules.length
before = rules.take(anchor).reject { |rule| docker_rules.include?(rule) }
after = rules.drop(anchor).reject { |rule| docker_rules.include?(rule) }
config['rules'] = before + docker_rules + after
# Keep the string form when Psych/YAML 1.1 has parsed unquoted off as false.
config['find-process-mode'] = 'off' if config['find-process-mode'] == false

stat = File.stat(path)
temporary = "#{path}.docker-policy.#{$$}"
begin
  File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, stat.mode & 0o777) do |file|
    file.write(YAML.dump(config))
    file.flush
    file.fsync
  end
  File.chown(stat.uid, stat.gid, temporary)
  File.rename(temporary, path)
ensure
  File.unlink(temporary) if File.exist?(temporary)
end
