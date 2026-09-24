#!/usr/bin/env python3
"""Erzeugt EarnoteiOS.xcodeproj (deterministisch) aus den Dateien im Ordner EarnoteiOS/.
Aufruf: python3 scripts/generate_ios_xcodeproj.py

Bewusst ein eigenes Projekt neben Earnote.xcodeproj: Die Mac-App und ihr Release-Weg bleiben unberührt.
Beide hängen am selben Kern (Packages/EarnoteKit). Plan: docs/IPHONE.md"""
import hashlib, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "EarnoteiOS"
SRC = os.path.join(ROOT, NAME)
PROJ = os.path.join(ROOT, f"{NAME}.xcodeproj")
# Dieselbe Version wie die Mac-App – steht nur in generate_xcodeproj.py
MARKETING_VERSION = next(l.split('"')[1] for l in open(os.path.join(ROOT, "scripts", "generate_xcodeproj.py"))
                         if l.startswith("MARKETING_VERSION ="))
_parts = (MARKETING_VERSION.split(".") + ["0", "0"])[:3]
BUILD_NUMBER = str(int(_parts[0]) * 10_000 + int(_parts[1]) * 100 + int(_parts[2]))

def uid(*parts):
    return hashlib.md5(("ios/" + "/".join(parts)).encode()).hexdigest()[:24].upper()

objects = {}
def add(key, body):
    objects[key] = body

def ftype(name):
    return {"swift": "sourcecode.swift", "plist": "text.plist.xml", "entitlements": "text.plist.entitlements",
            "xcassets": "folder.assetcatalog", "strings": "text.plist.strings"}.get(name.rsplit(".", 1)[-1], "text")

# Ordner als Gruppen, .xcassets als eine Datei
sources, resources, groups = [], [], {}
for dirpath, dirnames, filenames in os.walk(SRC):
    dirnames.sort()
    rel = os.path.relpath(dirpath, SRC)
    if ".xcassets" in rel:
        dirnames[:] = []
        continue
    g = groups.setdefault(rel, {"dirs": [], "files": []})
    for d in dirnames:
        (g["files"] if d.endswith(".xcassets") else g["dirs"]).append(d if d.endswith(".xcassets") else os.path.normpath(os.path.join(rel, d)))
        if d.endswith(".xcassets"):
            resources.append(os.path.normpath(os.path.join(rel, d)))
    for f in sorted(filenames):
        if f.startswith("."):
            continue
        g["files"].append(f)
        if f.endswith(".swift"):
            sources.append(os.path.normpath(os.path.join(rel, f)))

# Plattformneutrale Dateien der Mac-App, die das iPhone mitkompiliert (statt eines eigenen Moduls, das alles
# `public` machen müsste). Wer hier etwas einträgt, hält die Datei frei von AppKit außerhalb von `#if os(macOS)`.
SHARED = [
    "Earnote/Stores/LibraryStore.swift",
    "Earnote/Transcription/AppleSpeechTranscriber.swift",
    "Earnote/Transcription/TranscriberFactory.swift",
    "Earnote/AI/PlatformLLMClients.swift",
    "Earnote/AI/AppleIntelligenceClient.swift",
    "Earnote/AI/LocalModels.swift",
    "Earnote/App/DemoLibrary.swift",
]
# Übersetzungen: dieselbe Tabelle wie am Mac (Deutsch steht im Code)
LOCALIZED = {"en": "Earnote/Resources/en.lproj/Localizable.strings"}

refs = {}
for rel, g in groups.items():
    for f in g["files"]:
        path = os.path.normpath(os.path.join(rel, f))
        refs[path] = uid("ref", path)
        add(refs[path], f'{{isa = PBXFileReference; lastKnownFileType = {ftype(f)}; path = "{f}"; sourceTree = "<group>"; }};')
for rel, g in groups.items():
    children = [uid("group", d) for d in sorted(g["dirs"])] + [refs[os.path.normpath(os.path.join(rel, f))] for f in g["files"]]
    add(uid("group", rel), "{isa = PBXGroup; children = (" + "".join(f"{c}, " for c in children)
        + f'); path = "{NAME if rel == "." else os.path.basename(rel)}"; sourceTree = "<group>"; }};')

shared_refs = []
for path in SHARED:
    refs[path] = uid("shared", path)
    add(refs[path], f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{os.path.basename(path)}"; path = "{path}"; sourceTree = SOURCE_ROOT; }};')
    shared_refs.append(refs[path])
    sources.append(path)
loc_children = []
for language, path in LOCALIZED.items():
    ref = uid("loc", language)
    add(ref, f'{{isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = {language}; path = "{path}"; sourceTree = SOURCE_ROOT; }};')
    loc_children.append(ref)
LOC_GROUP = uid("locgroup")
add(LOC_GROUP, "{isa = PBXVariantGroup; children = (" + "".join(f"{c}, " for c in loc_children) + '); name = Localizable.strings; sourceTree = "<group>"; };')
SHARED_GROUP = uid("sharedgroup")
add(SHARED_GROUP, "{isa = PBXGroup; children = (" + "".join(f"{c}, " for c in shared_refs) + f"{LOC_GROUP}, " + '); name = "Gemeinsam mit dem Mac"; sourceTree = "<group>"; };')

PRODUCT = uid("product")
add(PRODUCT, f'{{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
PRODUCTS = uid("products")
add(PRODUCTS, f'{{isa = PBXGroup; children = ({PRODUCT}, ); name = Products; sourceTree = "<group>"; }};')
PACKAGE_REF_FILE = uid("pkgfile")
add(PACKAGE_REF_FILE, '{isa = PBXFileReference; lastKnownFileType = wrapper; path = "Packages/EarnoteKit"; sourceTree = "<group>"; };')
MAIN = uid("main")
add(MAIN, f'{{isa = PBXGroup; children = ({uid("group", ".")}, {SHARED_GROUP}, {PACKAGE_REF_FILE}, {PRODUCTS}, ); sourceTree = "<group>"; }};')

# Kern und ML aus dem lokalen Paket – dieselben wie in der Mac-App
PACKAGE = uid("localpkg")
add(PACKAGE, '{isa = XCLocalSwiftPackageReference; relativePath = "Packages/EarnoteKit"; };')
pkg_products, pkg_builds = [], []
for product in ["EarnoteCore", "EarnoteML"]:
    p, b = uid("pkgproduct", product), uid("pkgbuild", product)
    add(p, f'{{isa = XCSwiftPackageProductDependency; productName = {product}; }};')
    add(b, f'{{isa = PBXBuildFile; productRef = {p}; }};')
    pkg_products.append(p)
    pkg_builds.append(b)

def phase(kind, files):
    key = uid("phase", kind)
    add(key, f"{{isa = PBX{kind}BuildPhase; buildActionMask = 2147483647; files = (" + "".join(f"{f}, " for f in files)
        + "); runOnlyForDeploymentPostprocessing = 0; };")
    return key

def build_file(path):
    key = uid("build", path)
    add(key, f'{{isa = PBXBuildFile; fileRef = {refs[path]}; }};')
    return key

SOURCES = phase("Sources", [build_file(s) for s in sources])
FRAMEWORKS = phase("Frameworks", pkg_builds)
LOC_BUILD = uid("build", "Localizable.strings")
add(LOC_BUILD, f'{{isa = PBXBuildFile; fileRef = {LOC_GROUP}; }};')
RESOURCES = phase("Resources", [build_file(r) for r in resources] + [LOC_BUILD])

def settings(d):
    return "{" + "".join(f'{k} = "{v}"; ' for k, v in d.items()) + "}"

target_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD_NUMBER,
    "DEVELOPMENT_TEAM": os.environ.get("EARNOTE_TEAM", ""),
    "GENERATE_INFOPLIST_FILE": "YES",
    # Hintergrund-Audio und Hintergrundarbeit stehen hier; der Rest wird aus den INFOPLIST_KEY_* erzeugt
    "INFOPLIST_FILE": f"{NAME}/Resources/Info.plist",
    "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription": "Earnote schreibt deine Aufnahmen mit der Spracherkennung auf deinem iPhone mit.",
    "INFOPLIST_KEY_CFBundleDisplayName": "Earnote",
    "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
    "INFOPLIST_KEY_NSMicrophoneUsageDescription": "Earnote nimmt Vorlesungen und Meetings auf, um daraus Notizen zu schreiben. Die Aufnahme bleibt auf deinem iPhone.",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": "app.earnote.Earnote",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SDKROOT": "iphoneos",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "6.0",
    "TARGETED_DEVICE_FAMILY": "1",
}
project_debug = {"ONLY_ACTIVE_ARCH": "YES", "SWIFT_OPTIMIZATION_LEVEL": "-Onone", "ENABLE_TESTABILITY": "YES",
                 "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "DEBUG_INFORMATION_FORMAT": "dwarf", "SDKROOT": "iphoneos"}
project_release = {"SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "-O",
                   "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "SDKROOT": "iphoneos", "VALIDATE_PRODUCT": "YES"}

def config_list(name, debug, release):
    d, r, l = uid("cfg", name, "debug"), uid("cfg", name, "release"), uid("cfglist", name)
    add(d, f"{{isa = XCBuildConfiguration; buildSettings = {settings(debug)}; name = Debug; }};")
    add(r, f"{{isa = XCBuildConfiguration; buildSettings = {settings(release)}; name = Release; }};")
    add(l, f"{{isa = XCConfigurationList; buildConfigurations = ({d}, {r}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")
    return l

# Widget-Erweiterung: Live-Aktivität (Sperrbildschirm, Dynamic Island) und Steuerelement fürs Kontrollzentrum.
# Die Dateien unter EarnoteiOS/Shared/ (Aktivität, Intents) kompiliert sie mit.
WNAME = "EarnoteWidgets"
WSRC = os.path.join(ROOT, WNAME)
wfiles = sorted(f for f in os.listdir(WSRC) if not f.startswith("."))
wrefs = {}
for f in wfiles:
    wrefs[f] = uid("wref", f)
    add(wrefs[f], f'{{isa = PBXFileReference; lastKnownFileType = {ftype(f)}; path = "{f}"; sourceTree = "<group>"; }};')
WGROUP = uid("wgroup")
add(WGROUP, "{isa = PBXGroup; children = (" + "".join(f"{wrefs[f]}, " for f in wfiles) + f'); path = "{WNAME}"; sourceTree = "<group>"; }};')
wbuilds = []
for f in wfiles:
    if f.endswith(".swift"):
        wbuilds.append(uid("wbuild", f))
        add(wbuilds[-1], f"{{isa = PBXBuildFile; fileRef = {wrefs[f]}; }};")
for path in sources:
    if path.startswith("Shared/"):
        wbuilds.append(uid("wbuild", "shared", path))
        add(wbuilds[-1], f"{{isa = PBXBuildFile; fileRef = {refs[path]}; }};")
WSOURCES = uid("wphase", "sources")
add(WSOURCES, "{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (" + "".join(f"{b}, " for b in wbuilds)
    + "); runOnlyForDeploymentPostprocessing = 0; };")
# Dieselbe Übersetzungstabelle – Sperrbildschirm und Kontrollzentrum folgen der Sprache des iPhones
WLOC_BUILD = uid("wbuild", "Localizable.strings")
add(WLOC_BUILD, f'{{isa = PBXBuildFile; fileRef = {LOC_GROUP}; }};')
WRESOURCES = uid("wphase", "resources")
add(WRESOURCES, f"{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({WLOC_BUILD}, ); runOnlyForDeploymentPostprocessing = 0; }};")
WPRODUCT = uid("wproduct")
add(WPRODUCT, f'{{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = {WNAME}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};')
add(PRODUCTS, f'{{isa = PBXGroup; children = ({PRODUCT}, {WPRODUCT}, ); name = Products; sourceTree = "<group>"; }};')
add(MAIN, f'{{isa = PBXGroup; children = ({uid("group", ".")}, {WGROUP}, {SHARED_GROUP}, {PACKAGE_REF_FILE}, {PRODUCTS}, ); sourceTree = "<group>"; }};')
widget_settings = {k: target_settings[k] for k in ("CODE_SIGN_STYLE", "CURRENT_PROJECT_VERSION", "DEVELOPMENT_TEAM",
                   "IPHONEOS_DEPLOYMENT_TARGET", "MARKETING_VERSION", "SDKROOT", "SUPPORTED_PLATFORMS", "SWIFT_VERSION",
                   "TARGETED_DEVICE_FAMILY", "SWIFT_EMIT_LOC_STRINGS")}
widget_settings.update({
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": f"{WNAME}/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Earnote",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "app.earnote.Earnote.Widgets",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SKIP_INSTALL": "YES",
})
WTARGET = uid("wtarget")
add(WTARGET, f"{{isa = PBXNativeTarget; buildConfigurationList = {config_list('widget', widget_settings, widget_settings)}; "
             f"buildPhases = ({WSOURCES}, {WRESOURCES}, ); buildRules = (); dependencies = (); name = {WNAME}; productName = {WNAME}; "
             f'productReference = {WPRODUCT}; productType = "com.apple.product-type.app-extension"; }};')
EMBED_FILE = uid("embed", "file")
add(EMBED_FILE, f"{{isa = PBXBuildFile; fileRef = {WPRODUCT}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
EMBED = uid("embed", "phase")
add(EMBED, f'{{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({EMBED_FILE}, ); '
           f'name = "Embed Foundation Extensions"; runOnlyForDeploymentPostprocessing = 0; }};')
PROJECT = uid("project")
WPROXY, WDEPENDENCY = uid("wproxy"), uid("wdependency")
add(WPROXY, f"{{isa = PBXContainerItemProxy; containerPortal = {PROJECT}; proxyType = 1; remoteGlobalIDString = {WTARGET}; remoteInfo = {WNAME}; }};")
add(WDEPENDENCY, f"{{isa = PBXTargetDependency; target = {WTARGET}; targetProxy = {WPROXY}; }};")

TARGET = uid("target")
add(TARGET, f"{{isa = PBXNativeTarget; buildConfigurationList = {config_list('target', target_settings, target_settings)}; "
            f"buildPhases = ({SOURCES}, {FRAMEWORKS}, {RESOURCES}, {EMBED}, ); buildRules = (); dependencies = ({WDEPENDENCY}, ); name = {NAME}; "
            f"packageProductDependencies = (" + "".join(f"{p}, " for p in pkg_products) + f"); productName = {NAME}; "
            f'productReference = {PRODUCT}; productType = "com.apple.product-type.application"; }};')
add(PROJECT, f"{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2600; LastUpgradeCheck = 2600; }}; "
             f"buildConfigurationList = {config_list('project', project_debug, project_release)}; compatibilityVersion = \"Xcode 14.0\"; "
             f"developmentRegion = de; hasScannedForEncodings = 0; knownRegions = (de, en, Base, ); mainGroup = {MAIN}; "
             f"packageReferences = ({PACKAGE}, ); productRefGroup = {PRODUCTS}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({TARGET}, {WTARGET}, ); }};")

os.makedirs(os.path.join(PROJ, "project.xcworkspace"), exist_ok=True)
with open(os.path.join(PROJ, "project.pbxproj"), "w") as f:
    f.write("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 60;\n\tobjects = {\n")
    for k in sorted(objects):
        f.write(f"\t\t{k} = {objects[k]}\n")
    f.write(f"\t}};\n\trootObject = {PROJECT};\n}}\n")
with open(os.path.join(PROJ, "project.xcworkspace", "contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version = "1.0">\n   <FileRef location = "self:">\n   </FileRef>\n</Workspace>\n')

scheme_dir = os.path.join(PROJ, "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)
ref = (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{TARGET}" BuildableName = "{NAME}.app" '
       f'BlueprintName = "{NAME}" ReferencedContainer = "container:{NAME}.xcodeproj"></BuildableReference>')
with open(os.path.join(scheme_dir, f"{NAME}.xcscheme"), "w") as f:
    f.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
''')
print(f"{len(sources)} Swift-Dateien → {PROJ}")
