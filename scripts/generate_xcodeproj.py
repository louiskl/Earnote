#!/usr/bin/env python3
"""Erzeugt Earnote.xcodeproj (deterministisch) aus den Dateien im Ordner Earnote/.
Aufruf: python3 scripts/generate_xcodeproj.py"""
import hashlib, os

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

SOURCES = uid("phase", "sources")
add(SOURCES, "{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (" + "".join(f"{b}, " for b in build_files) + "); runOnlyForDeploymentPostprocessing = 0; };")
RESOURCES = uid("phase", "resources")
add(RESOURCES, f"{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ASSETS_BUILD}, ); runOnlyForDeploymentPostprocessing = 0; }};")
FRAMEWORKS = uid("phase", "frameworks")
add(FRAMEWORKS, f"{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (" + "".join(f"{b}, " for b in PKG_BUILDS) + f"); runOnlyForDeploymentPostprocessing = 0; }};")

def settings_block(d):
    out = []
    for k, v in d.items():
        vs = v if isinstance(v, str) and v.replace("_", "").replace(".", "").isalnum() and v else f'"{v}"'
        out.append(f"{k} = {vs}; ")
    return "{" + "".join(out) + "}"

common_target = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Earnote/Resources/Earnote.entitlements",
    "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "Earnote/Resources/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
    "MACOSX_DEPLOYMENT_TARGET": "15.0",
    "MARKETING_VERSION": "0.2.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "app.earnote.Earnote",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
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
TEST_FILE, TEST_BUILD, TEST_SOURCES = uid("test-file"), uid("test-build"), uid("test-sources")
TEST_GROUP, TEST_CONFIGS = uid("test-group"), uid("test-configs")
TEST_DEPENDENCY, TEST_PROXY = uid("test-dependency"), uid("test-proxy")
PROJECT = uid("project")
add(TEST_FILE, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Phase0Tests.swift; sourceTree = "<group>"; };')
add(TEST_GROUP, f'{{isa = PBXGroup; children = ({TEST_FILE}, ); path = Tests; sourceTree = "<group>"; }};')
add(TEST_BUILD, f'{{isa = PBXBuildFile; fileRef = {TEST_FILE}; }};')
add(TEST_SOURCES, f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({TEST_BUILD}, ); runOnlyForDeploymentPostprocessing = 0; }};')
add(TEST_PRODUCT, '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = EarnoteTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };')
add(PRODUCTS_GROUP, f'{{isa = PBXGroup; children = ({PRODUCT}, {TEST_PRODUCT}, ); name = Products; sourceTree = "<group>"; }};')
add(MAIN_GROUP, f'{{isa = PBXGroup; children = ({group_key(".")}, {PACKAGE_GROUP}, {TEST_GROUP}, {PRODUCTS_GROUP}, ); sourceTree = "<group>"; }};')
test_settings = {
    "PRODUCT_BUNDLE_IDENTIFIER": "app.earnote.tests", "PRODUCT_NAME": "$(TARGET_NAME)",
    "GENERATE_INFOPLIST_FILE": "YES", "SWIFT_VERSION": "5.0", "CODE_SIGN_IDENTITY": "-",
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
