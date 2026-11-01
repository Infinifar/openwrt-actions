#!/usr/bin/env ruby
# Reapply only the dedicated GitHub routes after OpenClash transformations.
require 'yaml'

path = ARGV.fetch(0)
config = YAML.safe_load_file(path, aliases: true)
groups = Array(config['proxy-groups'])
# Downloaded, unrelated profiles without this strategy remain byte-identical.
exit 0 unless groups.any? { |group| group['name'] == 'GitHub' }

url = 'https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/GitHub/GitHub.yaml'
providers = config['rule-providers'] ||= {}
existing = providers['GitHub']
if existing && (!existing.is_a?(Hash) || ![url, "https://ghproxy.wegod.cc/#{url}"].include?(existing['url']))
  abort 'GitHub policy: custom provider URL conflicts; not overwriting it.'
end
old_rules = Array(config['rules'])
if old_rules.any? { |rule| rule.start_with?('RULE-SET,GitHub,') && rule != 'RULE-SET,GitHub,GitHub' }
  abort 'GitHub policy: custom provider route conflicts; not overwriting it.'
end
providers['GitHub'] = (existing || {}).merge(
  'type' => 'http', 'behavior' => 'classical', 'format' => 'yaml',
  'url' => url, 'path' => './rule_provider/GitHub.yaml', 'interval' => 43_200
)
domains = %w[github.com githubusercontent.com githubassets.com githubapp.com
             github.io github.dev github.blog githubstatus.com]
owned = ['DOMAIN,api.githubcopilot.com,GitHub']
owned << 'DOMAIN-SUFFIX,ghcr.io,Docker' if groups.any? { |group| group['name'] == 'Docker' }
owned += domains.map { |domain| "DOMAIN-SUFFIX,#{domain},GitHub" }
owned << 'RULE-SET,GitHub,GitHub'
remaining = old_rules.reject { |rule| owned.include?(rule) }
# Preserve the exact leading QUIC/OpenAI/Google safety prefix. Put GitHub
# before broad direct/download/media rules, not in front of scoped QUIC.
safety = %w[openai.com chatgpt.com oaistatic.com oaiusercontent.com
            openai.com.cdn.cloudflare.net chatgpt.com.cdn.cloudflare.net]
            .map { |domain| "DOMAIN-SUFFIX,#{domain},AI" }
safety += %w[antigravity.google gemini.google.com generativelanguage.googleapis.com]
            .map { |domain| "DOMAIN-SUFFIX,#{domain},Google" }
anchor = 0
while anchor < remaining.size &&
      (safety.include?(remaining[anchor]) || remaining[anchor].start_with?('AND,((NETWORK,UDP),(DST-PORT,443),'))
  anchor += 1
end
config['rules'] = remaining.take(anchor) + owned + remaining.drop(anchor)
config['find-process-mode'] = 'off' if config['find-process-mode'] == false

# Same owner/mode and atomic replacement: a full filesystem must not truncate.
stat = File.stat(path)
temporary = "#{path}.github-policy.#{$$}"
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
