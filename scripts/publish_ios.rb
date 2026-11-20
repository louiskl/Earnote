#!/usr/bin/env ruby
# iPhone/iPad-Fassung in den App Store bringen – in einem Rutsch, wie publish_release.sh für den Mac:
#
#   ruby scripts/publish_ios.rb                 # baut, lädt hoch, reicht ein
#   ruby scripts/publish_ios.rb --build 202611191139   # schon hochgeladenen (z. B. per TestFlight getesteten) Build nehmen
#   ruby scripts/publish_ios.rb --dry-run       # nur prüfen und lesen, nichts hochladen, nichts ändern
#
# 1. Version aus scripts/generate_xcodeproj.py, Texte für „Neu in dieser Version“ aus docs/releases/<Version>.appstore.json
#    ({"de-DE": "…", "en-US": "…", …} – je Sprache des Store-Eintrags ein Text)
# 2. baut und lädt hoch (publish_ios_testflight.sh) – oder nimmt den Build aus --build
# 3. wartet, bis Apple den Build verarbeitet hat
# 4. legt die Version an (oder nimmt die offene), hängt den Build an, trägt die Texte ein und liest sie zurück
# 5. fragt noch einmal und reicht zur Prüfung ein; nach der Freigabe erscheint die Version von selbst
#
# Zugang: scripts/appstoreconnect.env + scripts/AuthKey.p8 (siehe scripts/asc.rb). Der Schlüssel braucht die Rolle
# „App-Manager“ oder „Admin“, sonst lehnt Apple das Einreichen ab.
require_relative 'asc'
require 'json'

# Umlaute in Dateien und Texten – auch wenn das Terminal keine UTF-8-Umgebung setzt
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

APP_ID = '6815681807'
ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)

def fail!(message) = abort("✗ #{message}")
def step(message) = puts("▸ #{message}")

dry = ARGV.include?('--dry-run')
build_number = ARGV[ARGV.index('--build') + 1] if ARGV.include?('--build')

version = File.read('scripts/generate_xcodeproj.py')[/^MARKETING_VERSION = "([0-9.]+)"/, 1] or fail!('Version nicht gefunden')
notes_path = "docs/releases/#{version}.appstore.json"
step "Prüfe Voraussetzungen für Earnote #{version} (iPhone/iPad)#{dry ? ' – Trockenlauf' : ''} …"
fail!("Texte fehlen: #{notes_path}") unless File.exist?(notes_path)
notes = JSON.parse(File.read(notes_path))
fail!("#{notes_path}: leerer Text bei #{notes.select { |_, t| t.to_s.strip.empty? }.keys.join(', ')}") if notes.any? { |_, t| t.to_s.strip.empty? }
too_long = notes.select { |_, t| t.length > 4000 }.keys
fail!("#{notes_path}: zu lang (über 4000 Zeichen) bei #{too_long.join(', ')}") unless too_long.empty?
unless dry
  fail!('Nicht auf main') unless `git rev-parse --abbrev-ref HEAD`.strip == 'main'
  fail!('Es gibt ungesicherte Änderungen (git status)') unless `git status --porcelain`.strip.empty?
  system('git fetch -q origin main')
  fail!('main ist nicht auf dem Stand von origin/main (git pull)') unless `git rev-parse HEAD` == `git rev-parse origin/main`
end

# Gibt es die Version schon – und ist sie noch offen?
code, json = ASC.request('GET', "/v1/apps/#{APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=#{version}")
fail!("App Store Connect: #{ASC.error(json)} (HTTP #{code})") unless code == 200
existing = json['data'].first
editable = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY]
if existing
  state = existing['attributes']['appStoreState']
  fail!("#{version} ist schon veröffentlicht (#{state}) – Version in generate_xcodeproj.py erhöhen") if state == 'READY_FOR_SALE'
  fail!("#{version} ist gerade bei Apple (#{state}) – erst zurückziehen oder abwarten") unless editable.include?(state)
  step "Version #{version} gibt es schon (#{state}) – wird weiterverwendet"
else
  step "Version #{version} wird neu angelegt"
end

if dry
  step "Texte für #{notes.keys.sort.join(', ')} gefunden"
  puts '✓ Trockenlauf: alles bereit. Ohne --dry-run wird hochgeladen und eingereicht.'
  exit
end

print "Earnote #{version} für iPhone/iPad #{build_number ? "mit Build #{build_number} " : ''}einreichen? [j/N] "
fail!('Abgebrochen.') unless %w[j J].include?($stdin.gets.to_s.strip)

# 2. Bauen und hochladen
unless build_number
  output = `./scripts/publish_ios_testflight.sh 2>&1`
  puts output.lines.last(3)
  fail!('Hochladen fehlgeschlagen') unless $?.success? && output.include?('✓ Hochgeladen')
  build_number = output[/Earnote #{Regexp.escape(version)} \((\d+)\)/, 1] or fail!('Buildnummer nicht erkannt')
end

# 3. Warten, bis Apple den Build verarbeitet hat (meist 10–30 Minuten)
step "Warte auf die Verarbeitung von Build #{build_number} …"
build_id = nil
90.times do
  code, json = ASC.request('GET', "/v1/builds?filter[app]=#{APP_ID}&filter[version]=#{build_number}&limit=1")
  b = code == 200 ? json['data'].first : nil
  case b&.dig('attributes', 'processingState')
  when 'VALID' then build_id = b['id']; break
  when 'INVALID', 'FAILED' then fail!("Apple hat Build #{build_number} abgelehnt – Mail von App Store Connect lesen")
  end
  sleep 30
end
fail!("Build #{build_number} ist nach 45 Minuten nicht fertig – später mit --build #{build_number} weitermachen") unless build_id

# 4. Version anlegen oder nehmen, Build anhängen
version_id = existing&.dig('id')
if version_id
  code, json = ASC.request('PATCH', "/v1/appStoreVersions/#{version_id}/relationships/build",
                           { data: { type: 'builds', id: build_id } })
  fail!("Build anhängen: #{ASC.error(json)}") unless [200, 204].include?(code)
else
  code, json = ASC.request('POST', '/v1/appStoreVersions', {
    data: { type: 'appStoreVersions',
            # Nach der Freigabe von selbst veröffentlichen
            attributes: { platform: 'IOS', versionString: version, releaseType: 'AFTER_APPROVAL',
                          copyright: "#{Time.now.year} Louis Klinke" },
            relationships: { app: { data: { type: 'apps', id: APP_ID } },
                             build: { data: { type: 'builds', id: build_id } } } }
  })
  fail!("Version anlegen: #{ASC.error(json)}") unless code == 201
  version_id = json['data']['id']
end
step "Version #{version} mit Build #{build_number}"

# Texte eintragen und zurücklesen – fertig ist es erst, wenn Apple sie so zurückgibt
code, json = ASC.request('GET', "/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations?limit=50")
fail!("Sprachen lesen: #{ASC.error(json)}") unless code == 200
locales = json['data'].to_h { |l| [l['attributes']['locale'], l['id']] }
missing = locales.keys - notes.keys
fail!("#{notes_path}: Text fehlt für #{missing.join(', ')}") unless missing.empty?
locales.each do |locale, id|
  code, json = ASC.request('PATCH', "/v1/appStoreVersionLocalizations/#{id}",
                           { data: { type: 'appStoreVersionLocalizations', id: id, attributes: { whatsNew: notes[locale] } } })
  fail!("Text #{locale}: #{ASC.error(json)}") unless code == 200
end
code, json = ASC.request('GET', "/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations?limit=50")
wrong = json['data'].reject { |l| l['attributes']['whatsNew'] == notes[l['attributes']['locale']] }
fail!("Texte stimmen nach dem Eintragen nicht bei #{wrong.map { |l| l['attributes']['locale'] }.join(', ')}") unless wrong.empty?
step "„Neu in dieser Version“ in #{locales.size} Sprachen eingetragen"

# 5. Einreichen
code, json = ASC.request('POST', '/v1/reviewSubmissions', {
  data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' },
          relationships: { app: { data: { type: 'apps', id: APP_ID } } } }
})
fail!("Einreichen: #{ASC.error(json)} – braucht der Schlüssel die Rolle App-Manager?") unless code == 201
submission = json['data']['id']
code, json = ASC.request('POST', '/v1/reviewSubmissionItems', {
  data: { type: 'reviewSubmissionItems',
          relationships: { reviewSubmission: { data: { type: 'reviewSubmissions', id: submission } },
                           appStoreVersion: { data: { type: 'appStoreVersions', id: version_id } } } }
})
fail!("Einreichen: #{ASC.error(json)}") unless code == 201
# Apple antwortet hier manchmal erst nach Minuten – dann zählt, was danach dasteht
ASC.request('PATCH', "/v1/reviewSubmissions/#{submission}",
            { data: { type: 'reviewSubmissions', id: submission, attributes: { submitted: true } } }, timeout: 300)
state = nil
10.times do
  _, json = ASC.request('GET', "/v1/appStoreVersions/#{version_id}?fields[appStoreVersions]=appStoreState")
  state = json.dig('data', 'attributes', 'appStoreState')
  break if %w[WAITING_FOR_REVIEW IN_REVIEW].include?(state)
  sleep 15
end
fail!("Eingereicht, aber Apple meldet #{state.inspect} – in App Store Connect nachsehen") unless %w[WAITING_FOR_REVIEW IN_REVIEW].include?(state)
puts "✓ Earnote #{version} (Build #{build_number}) ist zur Prüfung eingereicht. Nach der Freigabe erscheint sie von selbst."
