# Kleiner Client für die App Store Connect API (ES256-JWT, ohne Gems).
#
# Zugang: scripts/appstoreconnect.env (ASC_KEY_ID, ASC_ISSUER_ID) und scripts/AuthKey.p8 – beide nicht im Repo.
# Umgebungsvariablen ASC_KEY_ID / ASC_ISSUER_ID / ASC_P8 gehen vor. Gibt nie Schlüsselmaterial aus.
#
#   ruby scripts/asc.rb GET '/v1/apps/6815681807/appStoreVersions?limit=1'
#
# Als Bibliothek: require_relative 'asc' → ASC.request('GET', pfad) → [Statuscode, JSON]
Encoding.default_external = Encoding::UTF_8
require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'

module ASC
  DIR = File.expand_path(__dir__)

  # Zugangsdateien liegen nicht im Repo – in einem Zweig-Ordner (git worktree) also nur im Haupt-Checkout
  def self.find(name)
    common = `git -C #{DIR.inspect} rev-parse --path-format=absolute --git-common-dir 2>/dev/null`.strip
    [DIR, (File.join(File.dirname(common), 'scripts') unless common.empty?)].compact
      .map { |dir| File.join(dir, name) }.find { |path| File.exist?(path) }
  end

  def self.env_file
    path = find('appstoreconnect.env')
    return {} unless path
    File.readlines(path).each_with_object({}) do |line, h|
      key, value = line.strip.split('=', 2)
      h[key] = value if key && value && !key.start_with?('#')
    end
  end

  def self.credentials
    file = env_file
    key = ENV['ASC_KEY_ID'] || file['ASC_KEY_ID'] or abort '✗ ASC_KEY_ID fehlt (scripts/appstoreconnect.env)'
    issuer = ENV['ASC_ISSUER_ID'] || file['ASC_ISSUER_ID'] or abort '✗ ASC_ISSUER_ID fehlt (scripts/appstoreconnect.env)'
    p8 = ENV['ASC_P8'] ? File.expand_path(ENV['ASC_P8']) : find('AuthKey.p8')
    abort '✗ Privater Schlüssel fehlt: scripts/AuthKey.p8' unless p8 && File.exist?(p8)
    [key, issuer, p8]
  end

  def self.b64(data) = Base64.urlsafe_encode64(data).delete('=')

  def self.jwt
    key_id, issuer, p8 = credentials
    now = Time.now.to_i
    input = "#{b64(JSON.dump(alg: 'ES256', kid: key_id, typ: 'JWT'))}." \
            "#{b64(JSON.dump(iss: issuer, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1'))}"
    der = OpenSSL::PKey::EC.new(File.read(p8)).sign(OpenSSL::Digest::SHA256.new, input)
    # DER → r||s (je 32 Byte), wie JOSE es für ES256 will
    r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
    "#{input}.#{b64(r + s)}"
  end

  # Antwort als [Statuscode, JSON] – bei Zeitüberschreitung [0, {}], damit der Aufrufer nachlesen kann
  def self.request(method, path, body = nil, timeout: 90)
    uri = URI("https://api.appstoreconnect.apple.com#{path}")
    req = Net::HTTP.const_get(method.capitalize).new(uri)
    req['Authorization'] = "Bearer #{jwt}"
    req['Content-Type'] = 'application/json'
    req.body = body.is_a?(String) ? body : JSON.dump(body) if body
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: timeout, open_timeout: 30) { |h| h.request(req) }
    json = res.body.to_s.empty? ? {} : (JSON.parse(res.body) rescue { 'raw' => res.body })
    [res.code.to_i, json]
  rescue Net::ReadTimeout, Net::OpenTimeout
    [0, {}]
  end

  # Erste Fehlermeldung von Apple, lesbar
  def self.error(json)
    e = (json['errors'] || []).first or return json.to_s[0, 300]
    [e['title'], e['detail']].compact.join(': ')
  end
end

if $PROGRAM_NAME == __FILE__
  method, path, body = ARGV
  abort 'Aufruf: ruby scripts/asc.rb <GET|POST|PATCH|DELETE> <pfad> [json]' unless method && path
  code, json = ASC.request(method, path, body)
  puts "HTTP #{code}"
  puts JSON.pretty_generate(json) unless json.empty?
end
