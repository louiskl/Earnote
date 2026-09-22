#!/usr/bin/env python3
"""Erzeugt Earnote.xcodeproj (deterministisch) aus den Dateien im Ordner Earnote/.
Aufruf: python3 scripts/generate_xcodeproj.py"""
import hashlib, os, pathlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Earnote")
PROJ = os.path.join(ROOT, "Earnote.xcodeproj")

def uid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()

objects = {}
def add(key, body):
    objects[key] = body

swift_files, groups = [], {}
for dirpath, dirnames, filenames in os.walk(SRC):
    dirnames.sort()
    rel = os.path.relpath(dirpath, SRC)
    if rel.endswith(".xcassets") or ".xcassets" in rel:
        dirnames[:] = []
        continue
    groups.setdefault(rel, {"dirs": [], "files": []})
    for d in dirnames:
        if d.endswith(".xcassets"):
            groups[rel]["files"].append(d)
        else:
            groups[rel]["dirs"].append(os.path.normpath(os.path.join(rel, d)))
    for f in sorted(filenames):
        if f.startswith("."):
            continue
        groups[rel]["files"].append(f)
        if f.endswith(".swift"):
            swift_files.append(os.path.normpath(os.path.join(rel, f)))

def ftype(name):
    return {"swift": "sourcecode.swift", "plist": "text.plist.xml", "entitlements": "text.plist.entitlements",
            "xcassets": "folder.assetcatalog"}.get(name.rsplit(".", 1)[-1], "text")

file_refs = {}
for rel, g in groups.items():
    for f in g["files"]:
        path = os.path.normpath(os.path.join(rel, f))
        key = uid("fileref", path)
        file_refs[path] = key
        add(key, f'{{isa = PBXFileReference; lastKnownFileType = {ftype(f)}; path = "{f}"; sourceTree = "<group>"; }};')

def group_key(rel):
    return uid("group", rel)

for rel, g in groups.items():
    children = [group_key(d) for d in sorted(g["dirs"])] + [file_refs[os.path.normpath(os.path.join(rel, f))] for f in g["files"]]
    name = "Earnote" if rel == "." else os.path.basename(rel)
    add(group_key(rel), "{isa = PBXGroup; children = (" + "".join(f"{c}, " for c in children) +
        f'); path = "{name}"; sourceTree = "<group>"; }};')

PRODUCT = uid("product")
add(PRODUCT, '{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Earnote.app; sourceTree = BUILT_PRODUCTS_DIR; };')
PRODUCTS_GROUP = uid("productsgroup")
add(PRODUCTS_GROUP, f'{{isa = PBXGroup; children = ({PRODUCT}, ); name = Products; sourceTree = "<group>"; }};')
MAIN_GROUP = uid("maingroup")
add(MAIN_GROUP, f'{{isa = PBXGroup; children = ({group_key(".")}, {PRODUCTS_GROUP}, ); sourceTree = "<group>"; }};')

# Swift Package: lokal unter Packages/EarnoteKit. Die Drittanbieter-Pakete (WhisperKit, MLX, HuggingFace,
# Transformers) sind dort in Package.swift eingetragen.
LOCAL_PACKAGE = uid("localpkg", "EarnoteKit")
add(LOCAL_PACKAGE, '{isa = XCLocalSwiftPackageReference; relativePath = "Packages/EarnoteKit"; };')
PKG_REFS, PKG_PRODUCTS, PKG_BUILDS = [LOCAL_PACKAGE], [], []
for product in ["EarnoteCore", "EarnoteML"]:
    prod = uid("pkgproduct", "EarnoteKit", product)
    add(prod, f'{{isa = XCSwiftPackageProductDependency; productName = {product}; }};')
    build = uid("pkgbuild", "EarnoteKit", product)
    add(build, f'{{isa = PBXBuildFile; productRef = {prod}; }};')
    PKG_PRODUCTS.append(prod)
    PKG_BUILDS.append(build)
# Sparkle: Selbstaktualisierung der App. Nur hier im App-Ziel – EarnoteKit bleibt frei davon,
# damit der Kern weiter für iOS baut.
SPARKLE_PACKAGE = uid("remotepkg", "Sparkle")
add(SPARKLE_PACKAGE, '{isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/sparkle-project/Sparkle"; '
    'requirement = {kind = upToNextMajorVersion; minimumVersion = 2.8.0; }; };')
_sparkle_product = uid("pkgproduct", "Sparkle", "Sparkle")
add(_sparkle_product, f'{{isa = XCSwiftPackageProductDependency; package = {SPARKLE_PACKAGE}; productName = Sparkle; }};')
_sparkle_build = uid("pkgbuild", "Sparkle", "Sparkle")
add(_sparkle_build, f'{{isa = PBXBuildFile; productRef = {_sparkle_product}; }};')
PKG_REFS.append(SPARKLE_PACKAGE)
PKG_PRODUCTS.append(_sparkle_product)
PKG_BUILDS.append(_sparkle_build)

PACKAGE_GROUP = uid("group", "Packages")
add(PACKAGE_GROUP, '{isa = PBXFileReference; lastKnownFileType = wrapper; path = "Packages/EarnoteKit"; sourceTree = "<group>"; };')

build_files = []
for f in swift_files:
    key = uid("build", f)
    add(key, f'{{isa = PBXBuildFile; fileRef = {file_refs[f]}; }};')
    build_files.append(key)
assets_path = "Resources/Assets.xcassets"
ASSETS_BUILD = uid("build", assets_path)
add(ASSETS_BUILD, f'{{isa = PBXBuildFile; fileRef = {file_refs[assets_path]}; }};')

# Übersetzungen: Deutsch steht im Code, jede weitere Sprache liegt als <sprache>.lproj/*.strings daneben.
# Xcode braucht dafür je Datei eine „Variantengruppe“ mit den Sprachen als Kindern.
LOCALIZED_BUILDS = []
localized_groups = []
resources_dir = pathlib.Path(SRC) / "Resources"
languages = sorted(d.name[: -len(".lproj")] for d in resources_dir.iterdir()
                   if d.is_dir() and d.name.endswith(".lproj"))
for table in ["Localizable.strings", "InfoPlist.strings"]:
    children = []
    for language in languages:
        rel = f"{language}.lproj/{table}"
        if not (resources_dir / rel).exists():
            continue
        ref = uid("locfile", rel)
        # Pfad vom Projektordner aus, weil die Variantengruppe nicht unter der Gruppe „Earnote“ hängt
        add(ref, f'{{isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = {language}; '
                 f'path = "Earnote/Resources/{rel}"; sourceTree = "<group>"; }};')
        children.append(ref)
    if not children:
        continue
    group = uid("locgroup", table)
    add(group, "{isa = PBXVariantGroup; children = (" + "".join(f"{c}, " for c in children)
        + f"); name = {table}; sourceTree = \"<group>\"; }};")
    build = uid("build", table)
    add(build, f'{{isa = PBXBuildFile; fileRef = {group}; }};')
    LOCALIZED_BUILDS.append(build)
    localized_groups.append(group)

SOURCES = uid("phase", "sources")
add(SOURCES, "{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (" + "".join(f"{b}, " for b in build_files) + "); runOnlyForDeploymentPostprocessing = 0; };")
RESOURCES = uid("phase", "resources")
add(RESOURCES, f"{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ASSETS_BUILD}, "
    + "".join(f"{b}, " for b in LOCALIZED_BUILDS) + "); runOnlyForDeploymentPostprocessing = 0; };")
FRAMEWORKS = uid("phase", "frameworks")
add(FRAMEWORKS, f"{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (" + "".join(f"{b}, " for b in PKG_BUILDS) + f"); runOnlyForDeploymentPostprocessing = 0; }};")

def settings_block(d):
    out = []
    for k, v in d.items():
        vs = v if isinstance(v, str) and v.replace("_", "").replace(".", "").isalnum() and v else f'"{v}"'
        out.append(f"{k} = {vs}; ")
    return "{" + "".join(out) + "}"

# Signatur des App-Ziels. Normalfall: ad-hoc, ohne Team, ohne iCloud – so baut das Projekt auf
# jedem Rechner ohne Entwicklerkonto. Nur für den einmaligen Lauf, der das CloudKit-Schema anlegt,
# setzt man EARNOTE_ICLOUD_DEV_TEAM=<Team-ID>: Dann signiert Xcode automatisch mit dem Konto und
# die App darf in die Entwicklungs-Umgebung von CloudKit schreiben. Danach wieder ohne die Variable
# erzeugen (siehe docs/ROADMAP.md, „iCloud-Sync einschalten“).
ICLOUD_DEV_TEAM = os.environ.get("EARNOTE_ICLOUD_DEV_TEAM", "")
APP_ENTITLEMENTS = ("Earnote/Resources/Earnote-iCloud-Development.entitlements" if ICLOUD_DEV_TEAM
                    else "Earnote/Resources/Earnote.entitlements")

# Die Version der App steht nur hier. Sparkle vergleicht Fassungen an der Buildnummer
# (CFBundleVersion), nicht am Namen – sie muss also mit jeder Fassung wachsen, sonst bietet die
# App ein Update nie an. Aus „0.9.4“ wird 904.
MARKETING_VERSION = "0.9.12"
_parts = (MARKETING_VERSION.split(".") + ["0", "0"])[:3]
BUILD_NUMBER = str(int(_parts[0]) * 10_000 + int(_parts[1]) * 100 + int(_parts[2]))

common_target = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_ENTITLEMENTS": APP_ENTITLEMENTS,
    "CODE_SIGN_IDENTITY": "Apple Development" if ICLOUD_DEV_TEAM else "-",
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": BUILD_NUMBER,
    "DEVELOPMENT_TEAM": ICLOUD_DEV_TEAM,
    "ENABLE_HARDENED_RUNTIME": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "Earnote/Resources/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
    "MACOSX_DEPLOYMENT_TARGET": "15.0",
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": "app.earnote.Earnote",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "6.0",
}
TCFG_D, TCFG_R = uid("cfg", "target", "debug"), uid("cfg", "target", "release")
add(TCFG_D, "{isa = XCBuildConfiguration; buildSettings = " + settings_block(common_target) + "; name = Debug; };")
add(TCFG_R, "{isa = XCBuildConfiguration; buildSettings = " + settings_block(common_target) + "; name = Release; };")

base = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "MACOSX_DEPLOYMENT_TARGET": "15.0",
    "SDKROOT": "macosx",
}
debug = dict(base, **{"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
                      "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
                      "SWIFT_OPTIMIZATION_LEVEL": "-Onone", "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE"})
release = dict(base, **{"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO",
                        "SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "-O", "MTL_ENABLE_DEBUG_INFO": "NO"})
PCFG_D, PCFG_R = uid("cfg", "proj", "debug"), uid("cfg", "proj", "release")
add(PCFG_D, "{isa = XCBuildConfiguration; buildSettings = " + settings_block(debug) + "; name = Debug; };")
add(PCFG_R, "{isa = XCBuildConfiguration; buildSettings = " + settings_block(release) + "; name = Release; };")

TLIST, PLIST = uid("cfglist", "target"), uid("cfglist", "proj")
add(TLIST, f"{{isa = XCConfigurationList; buildConfigurations = ({TCFG_D}, {TCFG_R}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")
add(PLIST, f"{{isa = XCConfigurationList; buildConfigurations = ({PCFG_D}, {PCFG_R}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")

TARGET = uid("target")
add(TARGET, f"{{isa = PBXNativeTarget; buildConfigurationList = {TLIST}; buildPhases = ({SOURCES}, {FRAMEWORKS}, {RESOURCES}, ); "
            f"buildRules = (); dependencies = (); name = Earnote; packageProductDependencies = (" + "".join(f"{p}, " for p in PKG_PRODUCTS) + f"); "
            f"productName = Earnote; productReference = {PRODUCT}; productType = \"com.apple.product-type.application\"; }};")
# Kleines, app-gehostetes Regressionstest-Target; die App-Buildsettings bleiben unverändert.
TEST_TARGET, TEST_PRODUCT = uid("test-target"), uid("test-product")
TEST_SOURCES = uid("test-sources")
TEST_GROUP, TEST_CONFIGS = uid("test-group"), uid("test-configs")
TEST_DEPENDENCY, TEST_PROXY = uid("test-dependency"), uid("test-proxy")
PROJECT = uid("project")
# Alle Testdateien im Ordner „Tests“
test_files = sorted(f.name for f in pathlib.Path("Tests").glob("*.swift"))
test_refs, test_builds = [], []
for name in test_files:
    ref, build = uid("test-file", name), uid("test-build", name)
    add(ref, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};')
    add(build, f'{{isa = PBXBuildFile; fileRef = {ref}; }};')
    test_refs.append(ref)
    test_builds.append(build)
add(TEST_GROUP, '{isa = PBXGroup; children = (' + "".join(f"{r}, " for r in test_refs) + '); path = Tests; sourceTree = "<group>"; };')
add(TEST_SOURCES, '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + "".join(f"{b}, " for b in test_builds) + '); runOnlyForDeploymentPostprocessing = 0; };')
add(TEST_PRODUCT, '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = EarnoteTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };')
add(PRODUCTS_GROUP, f'{{isa = PBXGroup; children = ({PRODUCT}, {TEST_PRODUCT}, ); name = Products; sourceTree = "<group>"; }};')
add(MAIN_GROUP, f'{{isa = PBXGroup; children = ({group_key(".")}, {PACKAGE_GROUP}, {TEST_GROUP}, {PRODUCTS_GROUP}, ); sourceTree = "<group>"; }};')
test_settings = {
    "PRODUCT_BUNDLE_IDENTIFIER": "app.earnote.tests", "PRODUCT_NAME": "$(TARGET_NAME)",
    "GENERATE_INFOPLIST_FILE": "YES", "SWIFT_VERSION": "6.0", "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGN_STYLE": "Manual", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Earnote.app/Contents/MacOS/Earnote",
    "BUNDLE_LOADER": "$(TEST_HOST)", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @loader_path/../Frameworks @executable_path/../Frameworks",
}
for name in ("Debug", "Release"):
    add(uid("test-config", name), "{isa = XCBuildConfiguration; buildSettings = " + settings_block(test_settings) + f"; name = {name}; }};")
add(TEST_CONFIGS, f'{{isa = XCConfigurationList; buildConfigurations = ({uid("test-config", "Debug")}, {uid("test-config", "Release")}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};')
add(TEST_PROXY, f'{{isa = PBXContainerItemProxy; containerPortal = {PROJECT}; proxyType = 1; remoteGlobalIDString = {TARGET}; remoteInfo = Earnote; }};')
add(TEST_DEPENDENCY, f'{{isa = PBXTargetDependency; target = {TARGET}; targetProxy = {TEST_PROXY}; }};')
add(TEST_TARGET, f'{{isa = PBXNativeTarget; buildConfigurationList = {TEST_CONFIGS}; buildPhases = ({TEST_SOURCES}, ); buildRules = (); dependencies = ({TEST_DEPENDENCY}, ); name = EarnoteTests; productName = EarnoteTests; productReference = {TEST_PRODUCT}; productType = "com.apple.product-type.bundle.unit-test"; }};')

add(PROJECT, f"{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; "
             f"TargetAttributes = {{{TARGET} = {{CreatedOnToolsVersion = 16.0; }}; }}; }}; buildConfigurationList = {PLIST}; "
             f"compatibilityVersion = \"Xcode 14.0\"; developmentRegion = de; hasScannedForEncodings = 0; knownRegions = (de, en, Base, ); "
             f"mainGroup = {MAIN_GROUP}; packageReferences = (" + "".join(f"{r}, " for r in PKG_REFS) + f"); productRefGroup = {PRODUCTS_GROUP}; projectDirPath = \"\"; "
             f"projectRoot = \"\"; targets = ({TARGET}, {TEST_TARGET}, ); }};")

os.makedirs(os.path.join(PROJ, "project.xcworkspace"), exist_ok=True)
with open(os.path.join(PROJ, "project.pbxproj"), "w") as f:
    f.write("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 60;\n\tobjects = {\n")
    for k in sorted(objects):
        f.write(f"\t\t{k} = {objects[k]}\n")
    f.write(f"\t}};\n\trootObject = {PROJECT};\n}}\n")
with open(os.path.join(PROJ, "project.xcworkspace", "contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version = "1.0">\n   <FileRef location = "self:">\n   </FileRef>\n</Workspace>\n')

# Schema, damit "Run" sofort funktioniert
sd = os.path.join(PROJ, "xcshareddata", "xcschemes")
os.makedirs(sd, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{TARGET}" BuildableName = "Earnote.app" BlueprintName = "Earnote" ReferencedContainer = "container:Earnote.xcodeproj"></BuildableReference>'
with open(os.path.join(sd, "Earnote.xcscheme"), "w") as f:
    f.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables><TestableReference skipped = "NO"><BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{TEST_TARGET}" BuildableName = "EarnoteTests.xctest" BlueprintName = "EarnoteTests" ReferencedContainer = "container:Earnote.xcodeproj"></BuildableReference></TestableReference></Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
''')
print(f"{len(swift_files)} Swift-Dateien → {PROJ}")
