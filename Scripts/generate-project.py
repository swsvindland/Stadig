#!/usr/bin/env python3
"""Writes Apps/LiftTrack/LiftTrack.xcodeproj: four targets over synchronized folders, linked to the
local Swift packages in Packages/. Run from the repo root: python3 Scripts/generate-project.py"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(ROOT, "Apps", "LiftTrack")
OUT = os.path.join(APP_DIR, "LiftTrack.xcodeproj")


def q(v):
    v = str(v)
    if v == "":
        return '""'
    safe = all(c.isalnum() or c in "._/-" for c in v)
    return v if safe else '"' + v.replace('"', '\\"') + '"'


def settings_block(d, indent="\t\t\t\t"):
    lines = []
    for k in sorted(d):
        v = d[k]
        key = q(k)
        if isinstance(v, list):
            lines.append(f"{indent}{key} = (")
            for item in v:
                lines.append(f"{indent}\t{q(item)},")
            lines.append(f"{indent});")
        else:
            lines.append(f"{indent}{key} = {q(v)};")
    return "\n".join(lines)


swift_common = {
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
    "SWIFT_VERSION": "6.0",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "MARKETING_VERSION": "1.0",
    "DEVELOPMENT_TEAM": "",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "GENERATE_INFOPLIST_FILE": "YES",
    "ENABLE_PREVIEWS": "YES",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
    "DEAD_CODE_STRIPPING": "YES",
}

app = dict(swift_common, **{
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/LiftTrack.entitlements",
    "INFOPLIST_FILE": "Config/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Lift Track",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.healthcare-fitness",
    "INFOPLIST_KEY_NSHealthShareUsageDescription": "Lift Track reads body weight, sleep, heart rate, HRV and workouts from other apps, so your training plan accounts for recovery and everything you do outside the gym.",
    "INFOPLIST_KEY_NSHealthUpdateUsageDescription": "Lift Track saves your sessions as strength workouts, and your waist and body-fat measurements.",
    "INFOPLIST_KEY_NSPhotoLibraryUsageDescription": "Lift Track saves progress photos you choose, for your own comparison.",
    "INFOPLIST_KEY_NSCameraUsageDescription": "Lift Track can take progress photos for your own comparison.",
    "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "IPHONEOS_DEPLOYMENT_TARGET": "26.1",
    "LD_RUNPATH_SEARCH_PATHS": "@executable_path/Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.svindland.lifttrack",
    "SDKROOT": "iphoneos",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) MAIN_APP",
    "TARGETED_DEVICE_FAMILY": "1,2",
})

widgets = dict(swift_common, **{
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/Widgets.entitlements",
    "INFOPLIST_FILE": "Config/Widgets-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Lift Track",
    "IPHONEOS_DEPLOYMENT_TARGET": "26.1",
    "LD_RUNPATH_SEARCH_PATHS": "@executable_path/Frameworks @executable_path/../../Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.svindland.lifttrack.widgets",
    "SDKROOT": "iphoneos",
    "SKIP_INSTALL": "YES",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "TARGETED_DEVICE_FAMILY": "1,2",
})

watch = dict(swift_common, **{
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/Watch.entitlements",
    "INFOPLIST_FILE": "Config/Watch-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Lift Track",
    "INFOPLIST_KEY_NSHealthShareUsageDescription": "Lift Track shows your heart rate during a session and uses it to time rests.",
    "INFOPLIST_KEY_NSHealthUpdateUsageDescription": "Lift Track saves sessions you run on your Watch to Apple Health.",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown",
    "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "dev.svindland.lifttrack",
    "INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "@executable_path/Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.svindland.lifttrack.watchkitapp",
    "SDKROOT": "watchos",
    "SKIP_INSTALL": "YES",
    "SUPPORTED_PLATFORMS": "watchos watchsimulator",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) WATCH_APP",
    "TARGETED_DEVICE_FAMILY": "4",
    "WATCHOS_DEPLOYMENT_TARGET": "26.1",
})

watch_widgets = dict(swift_common, **{
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/WatchWidgets.entitlements",
    "INFOPLIST_FILE": "Config/Widgets-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Lift Track",
    "LD_RUNPATH_SEARCH_PATHS": "@executable_path/Frameworks @executable_path/../../Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.svindland.lifttrack.watchkitapp.widgets",
    "SDKROOT": "watchos",
    "SKIP_INSTALL": "YES",
    "SUPPORTED_PLATFORMS": "watchos watchsimulator",
    "TARGETED_DEVICE_FAMILY": "4",
    "WATCHOS_DEPLOYMENT_TARGET": "26.1",
})

project_debug = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES", "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20", "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE", "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_STRICT_OBJC_MSGSEND": "YES", "ENABLE_TESTABILITY": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17", "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_NO_COMMON_BLOCKS": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES", "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE", "MTL_FAST_MATH": "YES",
    "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
}
project_release = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES", "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20", "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE", "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17", "GCC_NO_COMMON_BLOCKS": "YES",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES", "MTL_ENABLE_DEBUG_INFO": "NO", "MTL_FAST_MATH": "YES",
    "SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "-O",
}

ID = {}


def gid(name):
    if name not in ID:
        ID[name] = f"4C1F{len(ID) + 1:020X}"
    return ID[name]


PACKAGES = ["SystemCore", "ExerciseLibrary", "SystemStore", "HealthBridge", "LiftEngine"]

targets = [
    # name, product, product type, explicitFileType, settings, synchronized folders, package products
    ("LiftTrack", "LiftTrack.app", "com.apple.product-type.application", "wrapper.application", app,
     ["iOS", "Shared"], PACKAGES),
    ("LiftTrackWidgets", "LiftTrackWidgets.appex", "com.apple.product-type.app-extension", "wrapper.app-extension", widgets,
     ["Widgets", "Shared"], ["SystemCore"]),
    ("LiftTrackWatch", "LiftTrackWatch.app", "com.apple.product-type.application", "wrapper.application", watch,
     ["Watch", "Shared"], ["SystemCore", "ExerciseLibrary", "HealthBridge", "LiftEngine"]),
    ("LiftTrackWatchWidgets", "LiftTrackWatchWidgets.appex", "com.apple.product-type.app-extension", "wrapper.app-extension",
     watch_widgets, ["WatchWidgets", "Shared"], ["SystemCore"]),
]
# (host, embedded, phase name, dstSubfolderSpec, dstPath)
embeds = [
    ("LiftTrack", "LiftTrackWidgets", "Embed Foundation Extensions", 13, ""),
    ("LiftTrack", "LiftTrackWatch", "Embed Watch Content", 16, "$(CONTENTS_FOLDER_PATH)/Watch"),
    ("LiftTrackWatch", "LiftTrackWatchWidgets", "Embed Foundation Extensions", 13, ""),
]
# LIFT_NO_WATCH_EMBED=1 builds the iPhone app without the Watch app inside (handy while the Watch
# target doesn't build). Never commit a project generated this way.
if os.environ.get("LIFT_NO_WATCH_EMBED"):
    embeds = [e for e in embeds if e[1] != "LiftTrackWatch"]
config_files = ["Info.plist", "Watch-Info.plist", "Widgets-Info.plist", "LiftTrack.entitlements", "Widgets.entitlements",
                "Watch.entitlements", "WatchWidgets.entitlements"]
groups = ["iOS", "Shared", "Widgets", "Watch", "WatchWidgets"]
extra_files = ["LiftTrack.storekit"]

P = []
w = P.append
w("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n")

w("/* Begin PBXBuildFile section */")
for host, emb, *_ in embeds:
    prod = [t for t in targets if t[0] == emb][0][1]
    w(f"\t\t{gid('bf-' + emb)} /* {prod} in Embed */ = {{isa = PBXBuildFile; fileRef = {gid('prod-' + emb)} /* {prod} */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
for name, *_rest in targets:
    for pkg in _rest[-1]:
        w(f"\t\t{gid('pbf-' + name + pkg)} /* {pkg} in Frameworks */ = {{isa = PBXBuildFile; productRef = {gid('pdep-' + name + pkg)} /* {pkg} */; }};")
w("/* End PBXBuildFile section */\n")

w("/* Begin PBXContainerItemProxy section */")
for host, emb, *_ in embeds:
    w(f"\t\t{gid('proxy-' + emb)} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {gid('project')} /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {gid('target-' + emb)};\n\t\t\tremoteInfo = {emb};\n\t\t}};")
w("/* End PBXContainerItemProxy section */\n")

w("/* Begin PBXCopyFilesBuildPhase section */")
for host, emb, name, spec, path in embeds:
    prod = [t for t in targets if t[0] == emb][0][1]
    w(f"\t\t{gid('copy-' + emb)} /* {name} */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = {q(path)};\n\t\t\tdstSubfolderSpec = {spec};\n\t\t\tfiles = (\n\t\t\t\t{gid('bf-' + emb)} /* {prod} in Embed */,\n\t\t\t);\n\t\t\tname = {q(name)};\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
w("/* End PBXCopyFilesBuildPhase section */\n")

w("/* Begin PBXFileReference section */")
for name, prod, ptype, ftype, *_ in targets:
    w(f"\t\t{gid('prod-' + name)} /* {prod} */ = {{isa = PBXFileReference; explicitFileType = {q(ftype)}; includeInIndex = 0; path = {q(prod)}; sourceTree = BUILT_PRODUCTS_DIR; }};")
for f in config_files:
    t = "text.plist.xml" if f.endswith(".plist") else "text.plist.entitlements"
    w(f"\t\t{gid('cfg-' + f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = {t}; path = {q(f)}; sourceTree = \"<group>\"; }};")
for f in extra_files:
    w(f"\t\t{gid('extra-' + f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = text; path = {q(f)}; sourceTree = \"<group>\"; }};")
w("/* End PBXFileReference section */\n")

w("/* Begin PBXFileSystemSynchronizedRootGroup section */")
for g in groups:
    w(f"\t\t{gid('group-' + g)} /* {g} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = {q(g)};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
w("/* End PBXFileSystemSynchronizedRootGroup section */\n")

w("/* Begin PBXFrameworksBuildPhase section */")
for name, *_rest in targets:
    files = "".join(f"\t\t\t\t{gid('pbf-' + name + pkg)} /* {pkg} in Frameworks */,\n" for pkg in _rest[-1])
    w(f"\t\t{gid('fw-' + name)} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{files}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
w("/* End PBXFrameworksBuildPhase section */\n")

w("/* Begin PBXGroup section */")
children = "".join(f"\t\t\t\t{gid('group-' + g)} /* {g} */,\n" for g in groups)
extras = "".join(f"\t\t\t\t{gid('extra-' + f)} /* {f} */,\n" for f in extra_files)
w(f"\t\t{gid('main')} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{children}\t\t\t\t{gid('config')} /* Config */,\n{extras}\t\t\t\t{gid('products')} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
prods = "".join(f"\t\t\t\t{gid('prod-' + t[0])} /* {t[1]} */,\n" for t in targets)
w(f"\t\t{gid('products')} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{prods}\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
cfgs = "".join(f"\t\t\t\t{gid('cfg-' + f)} /* {f} */,\n" for f in config_files)
w(f"\t\t{gid('config')} /* Config */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{cfgs}\t\t\t);\n\t\t\tpath = Config;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
w("/* End PBXGroup section */\n")

w("/* Begin PBXNativeTarget section */")
for name, prod, ptype, ftype, settings, tgroups, pkgs in targets:
    phase_lines = f"\t\t\t\t{gid('src-' + name)} /* Sources */,\n\t\t\t\t{gid('fw-' + name)} /* Frameworks */,\n\t\t\t\t{gid('res-' + name)} /* Resources */,\n"
    deps = ""
    for host, emb, pname, *_ in embeds:
        if host == name:
            phase_lines += f"\t\t\t\t{gid('copy-' + emb)} /* {pname} */,\n"
            deps += f"\t\t\t\t{gid('dep-' + emb)} /* PBXTargetDependency */,\n"
    syn = "".join(f"\t\t\t\t{gid('group-' + g)} /* {g} */,\n" for g in tgroups)
    pdeps = "".join(f"\t\t\t\t{gid('pdep-' + name + pkg)} /* {pkg} */,\n" for pkg in pkgs)
    w(f"\t\t{gid('target-' + name)} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {gid('cl-' + name)};\n\t\t\tbuildPhases = (\n{phase_lines}\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{deps}\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n{syn}\t\t\t);\n\t\t\tname = {name};\n\t\t\tpackageProductDependencies = (\n{pdeps}\t\t\t);\n\t\t\tproductName = {name};\n\t\t\tproductReference = {gid('prod-' + name)} /* {prod} */;\n\t\t\tproductType = {q(ptype)};\n\t\t}};")
w("/* End PBXNativeTarget section */\n")

w("/* Begin PBXProject section */")
attrs = "".join(f"\t\t\t\t\t{gid('target-' + t[0])} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n\t\t\t\t\t}};\n" for t in targets)
tlist = "".join(f"\t\t\t\t{gid('target-' + t[0])} /* {t[0]} */,\n" for t in targets)
prefs = "".join(f"\t\t\t\t{gid('pkg-' + p)} /* XCLocalSwiftPackageReference \"../../Packages/{p}\" */,\n" for p in PACKAGES)
w(f"\t\t{gid('project')} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2700;\n\t\t\t\tLastUpgradeCheck = 2700;\n\t\t\t\tTargetAttributes = {{\n{attrs}\t\t\t\t}};\n\t\t\t}};\n\t\t\tbuildConfigurationList = {gid('cl-project')};\n\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n\t\t\tmainGroup = {gid('main')};\n\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpackageReferences = (\n{prefs}\t\t\t);\n\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {gid('products')} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n{tlist}\t\t\t);\n\t\t}};")
w("/* End PBXProject section */\n")

for section, prefix in [("PBXResourcesBuildPhase", "res"), ("PBXSourcesBuildPhase", "src")]:
    w(f"/* Begin {section} section */")
    for name, *_ in targets:
        label = "Resources" if prefix == "res" else "Sources"
        w(f"\t\t{gid(prefix + '-' + name)} /* {label} */ = {{\n\t\t\tisa = {section};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
    w(f"/* End {section} section */\n")

w("/* Begin PBXTargetDependency section */")
for host, emb, *_ in embeds:
    w(f"\t\t{gid('dep-' + emb)} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {gid('target-' + emb)} /* {emb} */;\n\t\t\ttargetProxy = {gid('proxy-' + emb)} /* PBXContainerItemProxy */;\n\t\t}};")
w("/* End PBXTargetDependency section */\n")

w("/* Begin XCBuildConfiguration section */")


def config(key, name, settings):
    w(f"\t\t{gid(key)} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings_block(settings)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};")


config("cfg-project-Debug", "Debug", project_debug)
config("cfg-project-Release", "Release", project_release)
for name, prod, ptype, ftype, settings, *_ in targets:
    config(f"cfg-{name}-Debug", "Debug", settings)
    config(f"cfg-{name}-Release", "Release", settings)
w("/* End XCBuildConfiguration section */\n")

w("/* Begin XCConfigurationList section */")
for key, label in [("project", 'PBXProject "LiftTrack"')] + [(t[0], f'PBXNativeTarget "{t[0]}"') for t in targets]:
    w(f"\t\t{gid('cl-' + key)} /* Build configuration list for {label} */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{gid(f'cfg-{key}-Debug')} /* Debug */,\n\t\t\t\t{gid(f'cfg-{key}-Release')} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};")
w("/* End XCConfigurationList section */\n")

w("/* Begin XCLocalSwiftPackageReference section */")
for p in PACKAGES:
    w(f"\t\t{gid('pkg-' + p)} /* XCLocalSwiftPackageReference \"../../Packages/{p}\" */ = {{\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = ../../Packages/{p};\n\t\t}};")
w("/* End XCLocalSwiftPackageReference section */\n")

w("/* Begin XCSwiftPackageProductDependency section */")
for name, *_rest in targets:
    for pkg in _rest[-1]:
        w(f"\t\t{gid('pdep-' + name + pkg)} /* {pkg} */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = {gid('pkg-' + pkg)} /* XCLocalSwiftPackageReference \"../../Packages/{pkg}\" */;\n\t\t\tproductName = {pkg};\n\t\t}};")
w("/* End XCSwiftPackageProductDependency section */")

w(f"\t}};\n\trootObject = {gid('project')} /* Project object */;\n}}\n")

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "project.pbxproj"), "w") as f:
    f.write("\n".join(P))


def scheme(name, target, buildable, launch_storekit=False, extra_build=()):
    entries = [(target, buildable)] + list(extra_build)
    build_entries = "".join(
        f"""         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{gid('target-' + t)}" BuildableName = "{b}" BlueprintName = "{t}" ReferencedContainer = "container:LiftTrack.xcodeproj"></BuildableReference>
         </BuildActionEntry>
""" for t, b in entries)
    storekit = """      <StoreKitConfigurationFileReference identifier = "../../LiftTrack.storekit"></StoreKitConfigurationFileReference>
""" if launch_storekit else ""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2700" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
{build_entries}      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES"></TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{gid('target-' + target)}" BuildableName = "{buildable}" BlueprintName = "{target}" ReferencedContainer = "container:LiftTrack.xcodeproj"></BuildableReference>
      </BuildableProductRunnable>
{storekit}   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{gid('target-' + target)}" BuildableName = "{buildable}" BlueprintName = "{target}" ReferencedContainer = "container:LiftTrack.xcodeproj"></BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""


schemes = os.path.join(OUT, "xcshareddata", "xcschemes")
os.makedirs(schemes, exist_ok=True)
with open(os.path.join(schemes, "LiftTrack.xcscheme"), "w") as f:
    f.write(scheme("LiftTrack", "LiftTrack", "LiftTrack.app", launch_storekit=True))
with open(os.path.join(schemes, "LiftTrackWatch.xcscheme"), "w") as f:
    f.write(scheme("LiftTrackWatch", "LiftTrackWatch", "LiftTrackWatch.app"))
print("Wrote", OUT)
