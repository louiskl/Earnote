import re, pathlib, collections

def keys_of(path):
    out = set()
    for line in pathlib.Path(path).read_text().split('\n'):
        m = re.match(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"', line)
        if m:
            out.add(m.group(1).replace('\\"', '"'))
    return out

app_keys = keys_of('Earnote/Resources/en.lproj/Localizable.strings')
core_keys = keys_of('Packages/EarnoteKit/Sources/EarnoteCore/Resources/en.lproj/Localizable.strings')
ml_keys = keys_of('Packages/EarnoteKit/Sources/EarnoteML/Resources/en.lproj/Localizable.strings')
known = app_keys | core_keys | ml_keys
print(f"Englische Einträge: App {len(app_keys)}, Core {len(core_keys)}, ML {len(ml_keys)}")

german = re.compile(r'[äöüßÄÖÜ]|(?:\b(?:der|die|das|und|nicht|mit|für|ist|wird|kann|noch|beim|zum|vom|eine|einen|dein|deine)\b)')
pattern = re.compile(r'(?:\bt\(|String\(localized:\s*|Text\(|\.help\(|Label\(|Button\(|Toggle\(|Picker\(|Menu\(|Section\(|TextField\(|NavigationLink\(|navigationTitle\(|LabeledContent\(|ContentUnavailableView\(|Link\(|PrimaryButton\()\s*"((?:[^"\\]|\\.)+)"')
missing = collections.defaultdict(list)
apps = ['Earnote', 'EarnoteiOS', 'EarnoteWidgets', 'EarnoteShare', 'Packages/EarnoteKit/Sources']
for f in [f for d in apps for f in pathlib.Path(d).rglob('*.swift')]:
    if '.build' in str(f) or 'DemoLibrary' in str(f):
        continue
    text = f.read_text()
    for i, line in enumerate(text.split('\n'), 1):
        if line.strip().startswith('//') or '#if DEBUG' in line:
            continue
        for m in pattern.finditer(line):
            s = m.group(1)
            if len(s) < 3 or not german.search(s):
                continue
            if '\\(' in s:          # Interpolation: Schlüssel enthält %@ o. ä.
                continue
            if s not in known:
                missing[str(f)].append((i, s))

total = sum(len(v) for v in missing.values())
print(f"\nOhne englische Entsprechung: {total}\n")
for f, items in sorted(missing.items(), key=lambda kv: -len(kv[1]))[:12]:
    print(f"{f}  ({len(items)})")
    for line, s in items[:4]:
        print(f"    {line}: {s[:95]}")
