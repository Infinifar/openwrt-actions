#!/usr/bin/env ruby
# Called after OpenClash's transformations. No subscription or API secrets here.
require 'yaml'

path = ARGV.fetch(0)
config = YAML.safe_load_file(path, aliases: true)
ai = Array(config['proxy-groups']).find { |group| group['name'] == 'AI' }
# Do not invent an AI group or reroute an unrelated downloaded configuration.
exit 0 unless ai

groups = config.fetch('proxy-groups')
countries = groups.select { |group| %w[HK SG JP US TW UK KR IN].include?(group['name'].to_s.split.last) }
country_names = countries.map { |group| group.fetch('name') }
raise 'AI requires at least one existing country group' if country_names.empty?
# Default to US when present; never reference a group absent from this profile.
country_names = country_names.partition { |name| name.split.last == 'US' }.flatten
# Owned manual leaf group. Do not change the country groups or their selection.
# Both conditions apply to the full node name, independently of their order.
us_ai_settings = {
  'name' => 'US-AI',
  'icon' => 'https://cdn.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/United_States.png',
  'type' => 'select', 'include-all-providers' => true, 'include-all-proxies' => true,
  'filter' => '^(?=.*美国圣何塞)(?=.*[567]).*$', 'empty-fallback' => 'REJECT'
}
us_ai = groups.find { |group| group['name'] == 'US-AI' }
if us_ai
  us_ai.replace(us_ai_settings)
else
  groups.insert(groups.index(countries.first), us_ai_settings)
end
google = groups.find { |group| group['name'] == 'Google' && group['type'] == 'select' }
google['proxies'] = (Array(google['proxies']) + ['US-AI']).uniq if google
# Prefer an existing US country without changing the other choices or their order.
# Saved controller selections remain intact; list order supplies new-install defaults.
proxy = groups.find { |group| group['name'] == 'Proxy' && group['type'] == 'select' }
if proxy
  default_us = country_names.find { |name| name.split.last == 'US' }
  choices = Array(proxy['proxies'])
  proxy['proxies'] = ([default_us].compact +
                      (choices - [default_us, 'US-AI']) + ['US-AI']).uniq
end
ai['type'] = 'select'
%w[proxies use include-all include-all-providers include-all-proxies filter exclude-filter url interval tolerance
   default-selected strategy lazy timeout max-failed-times expected-status
   uselightgbm collectdata sample-rate prefer-asn policy-priority].each { |key| ai.delete(key) }
# Preserve the original US-first default. US-AI is an optional pinned leaf selector.
ai['proxies'] = country_names + ['US-AI']
ai['empty-fallback'] = 'REJECT'
# Zashboard places AI in Strategy; US-AI remains a separate Nodes group.
icon_base = 'https://cdn.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/'
country_icons = {
  'HK' => 'Hong_Kong', 'SG' => 'Singapore', 'JP' => 'Japan',
  'US' => 'United_States', 'TW' => 'Taiwan', 'UK' => 'United_Kingdom',
  'KR' => 'Korea', 'IN' => 'India'
}
groups.each do |group|
  country = country_icons[group.fetch('name').split.last]
  group['icon'] = "#{icon_base}#{country}.png" if country
end
config['profile'] ||= {}
config['profile']['store-selected'] = true
# Psych uses YAML 1.1, in which an unquoted off parses as false. Mihomo needs
# the string, not the boolean, when this helper serializes a source profile.
config['find-process-mode'] = 'off'

# Cover core ChatGPT endpoints before broad direct/ad-block rules, even if a
# remote ruleset is temporarily unavailable. Do not force shared auth/CDN TLDs.
priority_rules = %w[openai.com chatgpt.com oaistatic.com oaiusercontent.com
                    openai.com.cdn.cloudflare.net chatgpt.com.cdn.cloudflare.net]
                    .map { |domain| "DOMAIN-SUFFIX,#{domain},AI" }
old_rules = Array(config['rules'])
# Domain-only QUIC guard: never reuse the classical AI/Google providers here,
# because those also contain IP/ASN rules which could block unrelated hosts.
# A group disable-udp flag is not a reject: unsupported UDP can match later rules.
quic_rules = %w[google openai anthropic github-copilot].map do |category|
  "AND,((NETWORK,UDP),(DST-PORT,443),(GEOSITE,#{category})),REJECT-DROP"
end
quic_domains = %w[antigravity.google copilot.microsoft.com sydney.bing.com
                  edgeservices.bing.com services.bingapis.com
                  gateway.bingviz.microsoft.net gateway.bingviz.microsoftapp.net
                  openai.com chatgpt.com oaistatic.com oaiusercontent.com
                  openai.com.cdn.cloudflare.net chatgpt.com.cdn.cloudflare.net]
quic_rules << "AND,((NETWORK,UDP),(DST-PORT,443),(OR,(#{quic_domains.map { |domain| "(DOMAIN-SUFFIX,#{domain})" }.join(',')}))),REJECT-DROP"
owned_rules = quic_rules + priority_rules
config['rules'] = owned_rules + old_rules.reject { |rule| owned_rules.include?(rule) }

# Atomic replacement avoids leaving a truncated config if the rootfs fills up.
stat = File.stat(path)
temporary = "#{path}.ai-policy.#{$$}"
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
