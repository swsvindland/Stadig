#!/usr/bin/env python3
"""Writes each app's Xcode project (Apps/<App>/<App>.xcodeproj): targets over synchronized folders,
linked to the local Swift packages in Packages/. Run from the repo root:

    python3 Scripts/generate-project.py              # every app
    python3 Scripts/generate-project.py MacroTrack   # just one (LiftTrack or MacroTrack)
"""
import hashlib
import json
import os
import re
import sys
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAM = "9HAG9PT8LJ"
# Each app's version (CFBundleShortVersionString), shared by its extensions and Watch app as the App
# Store requires. Bump it here when cutting a release branch, then run this script.
VERSIONS = {"LiftTrack": "1.0", "MacroTrack": "1.0"}


def q(v):
    v = str(v)
    if v == "":
        return '""'
    # Xcode quotes anything beyond letters, digits, "._/", so writing the same keeps its rewrites a no-op.
    safe = all(c.isalnum() or c in "._/" for c in v)
    return v if safe else '"' + v.replace('"', '\\"') + '"'


def canonical(text):
    """The project as Xcode itself writes it: each section's objects sorted by id and empty sections
    left out, so opening the project in Xcode doesn't rewrite it."""
    lines, out, i = text.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]
        if not (line.startswith("/* Begin ") and line.endswith(" section */")):
            out.append(line)
            i += 1
            continue
        end = lines.index(line.replace("/* Begin ", "/* End ", 1), i)
        objects = []
        for body_line in lines[i + 1:end]:
            if re.match(r"\t\t[0-9A-F]{24} ", body_line):
                objects.append([body_line])
            else:
                objects[-1].append(body_line)
        i = end + 1
        if objects:
            out.append(line)
            for obj in sorted(objects, key=lambda o: o[0][2:26]):
                out.extend(obj)
            out.append(lines[end])
        elif i < len(lines) and lines[i] == "":
            i += 1
    return "\n".join(out)


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
    # Xcode Cloud sets the build number of every archive it makes; this is only for local builds.
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": TEAM,
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "GENERATE_INFOPLIST_FILE": "YES",
    "ENABLE_PREVIEWS": "YES",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
    "DEAD_CODE_STRIPPING": "YES",
}

# Every app is one target that builds natively for iPhone, iPad, the Mac and Apple Vision Pro: the
# destination picks the SDK (SDKROOT auto). One bundle id across them means one App Store record,
# one purchase that unlocks every device (universal purchase) and one CloudKit container.
multiplatform = {
    "IPHONEOS_DEPLOYMENT_TARGET": "26.1",
    "MACOSX_DEPLOYMENT_TARGET": "26.1",
    "SDKROOT": "auto",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx xros xrsimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "TARGETED_DEVICE_FAMILY": "1,2,7",
    "XROS_DEPLOYMENT_TARGET": "26.1",
}

ios_app_common = dict(multiplatform, **{
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    # Vision Pro's icon is a stack of layers, an asset of its own.
    "ASSETCATALOG_COMPILER_APPICON_NAME[sdk=xr*]": "AppIconVision",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    # The Mac app runs in the App Sandbox (its own entitlements file) with the hardened runtime.
    "ENABLE_HARDENED_RUNTIME[sdk=macosx*]": "YES",
    "INFOPLIST_FILE": "Config/Info.plist",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.healthcare-fitness",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": "@executable_path/Frameworks",
    "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": "@executable_path/../Frameworks",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) MAIN_APP",
})

ios_widgets_common = dict(multiplatform, **{
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/Widgets.entitlements",
    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Config/Widgets-macOS.entitlements",
    "ENABLE_HARDENED_RUNTIME[sdk=macosx*]": "YES",
    "INFOPLIST_FILE": "Config/Widgets-Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": ["@executable_path/../Frameworks", "@executable_path/../../../../Frameworks"],
    "SKIP_INSTALL": "YES",
})


def unit_tests(host, bundle_id):
    """A unit test bundle hosted in the app, so tests can `@testable import` it, on any of its platforms."""
    settings = dict(swift_common, **multiplatform, **{
        "BUNDLE_LOADER": "$(TEST_HOST)",
        "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": ["@executable_path/../Frameworks", "@loader_path/../Frameworks"],
        "PRODUCT_BUNDLE_IDENTIFIER": f"{bundle_id}.tests",
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{host}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{host}",
    })
    del settings["ENABLE_PREVIEWS"]
    return settings


def ui_tests(host, bundle_id):
    """A UI test bundle that drives the app from outside, as a person would."""
    settings = dict(swift_common, **multiplatform, **{
        "PRODUCT_BUNDLE_IDENTIFIER": f"{bundle_id}.uitests",
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "TEST_TARGET_NAME": host,
    })
    del settings["ENABLE_PREVIEWS"]
    return settings


def watch_app(name, bundle_id, companion, extra):
    """A watchOS app embedded in its iPhone app, that also runs (and syncs) without the phone."""
    return dict(swift_common, **{
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_ENTITLEMENTS": "Config/Watch.entitlements",
        "INFOPLIST_FILE": "Config/Watch-Info.plist",
        "INFOPLIST_KEY_CFBundleDisplayName": name,
        "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown",
        "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": companion,
        "INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp": "YES",
        "LD_RUNPATH_SEARCH_PATHS": "@executable_path/Frameworks",
        "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
        "SDKROOT": "watchos",
        "SKIP_INSTALL": "YES",
        "SUPPORTED_PLATFORMS": "watchos watchsimulator",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) WATCH_APP",
        "TARGETED_DEVICE_FAMILY": "4",
        "WATCHOS_DEPLOYMENT_TARGET": "26.1",
    }, **extra)


def watch_widgets(name, bundle_id):
    """The Watch app's complications, a WidgetKit extension inside it."""
    return dict(swift_common, **{
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_ENTITLEMENTS": "Config/WatchWidgets.entitlements",
        "INFOPLIST_FILE": "Config/Widgets-Info.plist",
        "INFOPLIST_KEY_CFBundleDisplayName": name,
        "LD_RUNPATH_SEARCH_PATHS": ["@executable_path/Frameworks", "@executable_path/../../Frameworks"],
        "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
        "SDKROOT": "watchos",
        "SKIP_INSTALL": "YES",
        "SUPPORTED_PLATFORMS": "watchos watchsimulator",
        "TARGETED_DEVICE_FAMILY": "4",
        "WATCHOS_DEPLOYMENT_TARGET": "26.1",
    })


def test_targets(app, bundle_id):
    """The app's unit tests (Tests/) and UI tests (UITests/), as target tuples."""
    return [
        (f"{app}Tests", f"{app}Tests.xctest", "com.apple.product-type.bundle.unit-test", "wrapper.cfbundle",
         unit_tests(app, bundle_id), ["Tests"], []),
        (f"{app}UITests", f"{app}UITests.xctest", "com.apple.product-type.bundle.ui-testing", "wrapper.cfbundle",
         ui_tests(app, bundle_id), ["UITests"], []),
    ]


# MARK: - Stadig Lift

lift_app = dict(swift_common, **ios_app_common, **{
    "CODE_SIGN_ENTITLEMENTS": "Config/LiftTrack.entitlements",
    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Config/LiftTrack-macOS.entitlements",
    "INFOPLIST_KEY_CFBundleDisplayName": "Stadig Lift",
    "INFOPLIST_KEY_NSHealthShareUsageDescription": "Stadig Lift reads body weight, sleep, heart rate, HRV, steps and workouts from other apps, so your training plan accounts for recovery and everything you do outside the gym.",
    "INFOPLIST_KEY_NSHealthUpdateUsageDescription": "Stadig Lift saves your sessions as strength workouts, and your waist and body-fat measurements.",
    "INFOPLIST_KEY_NSPhotoLibraryUsageDescription": "Stadig Lift saves progress photos you choose, for your own comparison.",
    "INFOPLIST_KEY_NSCameraUsageDescription": "Stadig Lift can take progress photos for your own comparison.",
    "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
    # Xcode moved these two out of Config/Info.plist into build settings.
    "INFOPLIST_KEY_NSSupportsLiveActivitiesFrequentUpdates": "NO",
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.svindland.stadig.lift",
})

lift_widgets = dict(swift_common, **ios_widgets_common, **{
    "INFOPLIST_KEY_CFBundleDisplayName": "Stadig Lift",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.svindland.stadig.lift.widgets",
})

lift_watch = watch_app("Stadig Lift", "dev.svindland.stadig.lift.watchkitapp", "dev.svindland.stadig.lift", {
    "INFOPLIST_KEY_NSHealthShareUsageDescription": "Stadig Lift shows your heart rate during a session and uses it to time rests.",
    "INFOPLIST_KEY_NSHealthUpdateUsageDescription": "Stadig Lift saves sessions you run on your Watch to Apple Health.",
})

lift_watch_widgets = watch_widgets("Stadig Lift", "dev.svindland.stadig.lift.watchkitapp.widgets")

LIFT_PACKAGES = ["SystemCore", "ExerciseLibrary", "SystemStore", "SystemPurchases", "HealthBridge", "LiftEngine", "HubEngine"]
lift_embeds = [
    # (host, embedded, phase name, dstSubfolderSpec, dstPath, platform filter or None for every platform)
    ("LiftTrack", "LiftTrackWidgets", "Embed Foundation Extensions", 13, "", None),
    # Only the iPhone app carries the Watch app; the Mac and Vision Pro builds leave it out.
    ("LiftTrack", "LiftTrackWatch", "Embed Watch Content", 16, "$(CONTENTS_FOLDER_PATH)/Watch", "ios"),
    ("LiftTrackWatch", "LiftTrackWatchWidgets", "Embed Foundation Extensions", 13, "", None),
]
# LIFT_NO_WATCH_EMBED=1 builds the iPhone app without the Watch app inside (handy while the Watch
# target doesn't build). Never commit a project generated this way.
if os.environ.get("LIFT_NO_WATCH_EMBED"):
    lift_embeds = [e for e in lift_embeds if e[1] != "LiftTrackWatch"]

LIFT = {
    "name": "LiftTrack",
    "id_prefix": "4C1F",
    "packages": LIFT_PACKAGES,
    "targets": [
        # name, product, product type, explicitFileType, settings, synchronized folders, package products
        ("LiftTrack", "LiftTrack.app", "com.apple.product-type.application", "wrapper.application", lift_app,
         ["iOS", "Shared"], LIFT_PACKAGES),
        ("LiftTrackWidgets", "LiftTrackWidgets.appex", "com.apple.product-type.app-extension", "wrapper.app-extension",
         lift_widgets, ["Widgets", "Shared"], ["SystemCore"]),
        ("LiftTrackWatch", "LiftTrackWatch.app", "com.apple.product-type.application", "wrapper.application", lift_watch,
         ["Watch", "Shared"], ["SystemCore", "ExerciseLibrary", "HealthBridge", "LiftEngine"]),
        ("LiftTrackWatchWidgets", "LiftTrackWatchWidgets.appex", "com.apple.product-type.app-extension",
         "wrapper.app-extension", lift_watch_widgets, ["WatchWidgets", "Shared"], ["SystemCore"]),
    ] + test_targets("LiftTrack", "dev.svindland.stadig.lift"),
    "embeds": lift_embeds,
    "config_files": ["Info.plist", "Watch-Info.plist", "Widgets-Info.plist", "LiftTrack.entitlements", "LiftTrack-macOS.entitlements",
                     "Widgets.entitlements", "Widgets-macOS.entitlements", "Watch.entitlements", "WatchWidgets.entitlements"],
    "groups": ["iOS", "Shared", "Widgets", "Watch", "WatchWidgets", "Tests", "UITests"],
    "exceptions": [],
    "extra_files": ["LiftTrack.storekit", "LiftTrack.xctestplan", "LiftTrackUI.xctestplan"],
    # Each scheme's test plans: unit and integration tests (the default), and UI tests. The packages'
    # own tests run with swift test (Scripts/build.sh test); an app project can't list them in a plan.
    "test_plans": [("LiftTrack", ["LiftTrackTests"]), ("LiftTrackUI", ["LiftTrackUITests"])],
    "schemes": [("LiftTrack", "LiftTrack", "LiftTrack.app", True), ("LiftTrackWatch", "LiftTrackWatch", "LiftTrackWatch.app", False)],
}

# MARK: - Stadig Macro

macro_app = dict(swift_common, **ios_app_common, **{
    "CODE_SIGN_ENTITLEMENTS": "Config/MacroTrack.entitlements",
    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Config/MacroTrack-macOS.entitlements",
    "INFOPLIST_KEY_CFBundleDisplayName": "Stadig Macro",
    "INFOPLIST_KEY_NSHealthShareUsageDescription": "Stadig Macro reads your weight, height and body composition, so targets adapt to your real trend without retyping anything.",
    "INFOPLIST_KEY_NSHealthUpdateUsageDescription": "Stadig Macro saves the food you log and the weigh-ins you enter to Apple Health.",
    "INFOPLIST_KEY_NSCameraUsageDescription": "Stadig Macro uses the camera to scan barcodes and nutrition labels, and to log a meal from a photo. Photos are read on your device or with Private Cloud Compute and never stored.",
    "INFOPLIST_KEY_NSPhotoLibraryUsageDescription": "Stadig Macro can log a meal from a photo you choose.",
    # A running fast on the Lock Screen and in the Dynamic Island.
    "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
    "INFOPLIST_KEY_NSSupportsLiveActivitiesFrequentUpdates": "NO",
    # Xcode moved this out of Config/Info.plist into build settings, as it did for Stadig Lift.
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.svindland.stadig.macro",
})

macro_widgets = dict(swift_common, **ios_widgets_common, **{
    "INFOPLIST_KEY_CFBundleDisplayName": "Stadig Macro",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.svindland.stadig.macro.widgets",
})

MACRO_PACKAGES = ["SystemCore", "SystemStore", "SystemPurchases", "HealthBridge", "NutritionEngine", "FoodDatabase", "FoodIntelligence", "MealPlanner", "HubEngine"]

# The Watch app reads and writes the same CloudKit records as the phone (Records/), with no food
# catalog: an entry carries its own numbers, and FoodIntelligence and MealPlanner don't build for
# watchOS. It writes nothing to Health (the iPhone does, once), so it needs no HealthKit.
macro_watch = watch_app("Stadig Macro", "dev.svindland.stadig.macro.watchkitapp", "dev.svindland.stadig.macro", {})

macro_watch_widgets = watch_widgets("Stadig Macro", "dev.svindland.stadig.macro.watchkitapp.widgets")

macro_embeds = [
    # (host, embedded, phase name, dstSubfolderSpec, dstPath, platform filter or None for every platform)
    ("MacroTrack", "MacroTrackWidgets", "Embed Foundation Extensions", 13, "", None),
    # Only the iPhone app carries the Watch app; the Mac and Vision Pro builds leave it out.
    ("MacroTrack", "MacroTrackWatch", "Embed Watch Content", 16, "$(CONTENTS_FOLDER_PATH)/Watch", "ios"),
    ("MacroTrackWatch", "MacroTrackWatchWidgets", "Embed Foundation Extensions", 13, "", None),
]

MACRO = {
    "name": "MacroTrack",
    "id_prefix": "4D2E",
    "packages": MACRO_PACKAGES,
    "targets": [
        ("MacroTrack", "MacroTrack.app", "com.apple.product-type.application", "wrapper.application", macro_app,
         ["iOS", "Shared", "Catalogs", "Records"], MACRO_PACKAGES),
        # NutritionEngine for the fasting widget's phases, the same the app shows.
        ("MacroTrackWidgets", "MacroTrackWidgets.appex", "com.apple.product-type.app-extension", "wrapper.app-extension",
         macro_widgets, ["Widgets", "Shared"], ["SystemCore", "NutritionEngine"]),
        ("MacroTrackWatch", "MacroTrackWatch.app", "com.apple.product-type.application", "wrapper.application", macro_watch,
         ["Watch", "WatchShared", "Records"], ["SystemCore", "SystemStore", "NutritionEngine"]),
        ("MacroTrackWatchWidgets", "MacroTrackWatchWidgets.appex", "com.apple.product-type.app-extension",
         "wrapper.app-extension", macro_watch_widgets, ["WatchWidgets", "WatchShared"], ["SystemCore", "NutritionEngine"]),
    ] + test_targets("MacroTrack", "dev.svindland.stadig.macro"),
    "embeds": macro_embeds,
    "config_files": ["Info.plist", "Watch-Info.plist", "Widgets-Info.plist", "MacroTrack.entitlements", "MacroTrack-macOS.entitlements",
                     "Widgets.entitlements", "Widgets-macOS.entitlements", "Watch.entitlements", "WatchWidgets.entitlements"],
    "groups": ["iOS", "Shared", "Records", "Widgets", "Watch", "WatchShared", "WatchWidgets", "Catalogs", "Tests", "UITests"],
    # The catalog folder holds off.db (installed by Scripts/install-food-catalogs.sh, not in git) and its README.
    "exceptions": [("Catalogs", "MacroTrack", [".gitignore", "README.md"])],
    "extra_files": ["MacroTrack.storekit", "MacroTrack.xctestplan", "MacroTrackUI.xctestplan"],
    "test_plans": [("MacroTrack", ["MacroTrackTests"]), ("MacroTrackUI", ["MacroTrackUITests"])],
    "schemes": [("MacroTrack", "MacroTrack", "MacroTrack.app", True), ("MacroTrackWatch", "MacroTrackWatch", "MacroTrackWatch.app", False)],
}

APPS = {"LiftTrack": LIFT, "MacroTrack": MACRO}

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
    # Warnings are errors in Debug builds on CI (Xcode Cloud sets CI=TRUE, GitHub CI=true), which is
    # where tests build; local builds and Release archives only warn.
    "SWIFT_TREAT_WARNINGS_AS_ERRORS": "$(WARNINGS_AS_ERRORS_ON_CI_$(CI))",
    "WARNINGS_AS_ERRORS_ON_CI_TRUE": "YES",
    "WARNINGS_AS_ERRORS_ON_CI_true": "YES",
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


def generate(spec):
    app_name = spec["name"]
    out = os.path.join(ROOT, "Apps", app_name, f"{app_name}.xcodeproj")
    packages = spec["packages"]
    targets = spec["targets"]
    embeds = spec["embeds"]
    config_files = spec["config_files"]
    groups = spec["groups"]
    exceptions = spec["exceptions"]
    extra_files = spec["extra_files"]
    test_plans = spec.get("test_plans", [])
    # (test target, the app it tests): each test bundle depends on its app.
    tests = [(t[0], app_name) for t in targets if t[2].startswith("com.apple.product-type.bundle.")]
    ID = {}

    # Every synchronized folder must exist, and a test target needs at least one test: git doesn't
    # keep empty folders, so a clean clone would otherwise get a test bundle with nothing in it.
    for name, *_rest in targets:
        for folder in _rest[-2]:
            path = os.path.join(ROOT, "Apps", app_name, folder)
            if not os.path.isdir(path):
                sys.exit(f"Apps/{app_name}/{folder} doesn't exist (target {name})")
            if name.endswith("Tests") and not any(f.endswith(".swift") for _, _, files in os.walk(path) for f in files):
                sys.exit(f"Apps/{app_name}/{folder} has no Swift files, so {name} would be empty")

    def gid(name):
        # Derived from the name, not the order objects are written in, so adding a target or file
        # leaves every existing id alone.
        if name not in ID:
            ID[name] = spec["id_prefix"] + hashlib.sha1(f"{app_name}/{name}".encode()).hexdigest()[:20].upper()
        return ID[name]

    P = []
    w = P.append
    w("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n")

    w("/* Begin PBXBuildFile section */")
    for host, emb, phase_name, *_rest in embeds:
        prod = [t for t in targets if t[0] == emb][0][1]
        only = f"platformFilter = {_rest[-1]}; " if _rest[-1] else ""
        w(f"\t\t{gid('bf-' + emb)} /* {prod} in {phase_name} */ = {{isa = PBXBuildFile; fileRef = {gid('prod-' + emb)} /* {prod} */; {only}settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
    for name, *_rest in targets:
        for pkg in _rest[-1]:
            w(f"\t\t{gid('pbf-' + name + pkg)} /* {pkg} in Frameworks */ = {{isa = PBXBuildFile; productRef = {gid('pdep-' + name + pkg)} /* {pkg} */; }};")
    w("/* End PBXBuildFile section */\n")

    w("/* Begin PBXContainerItemProxy section */")
    for host, emb, *_ in embeds:
        w(f"\t\t{gid('proxy-' + emb)} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {gid('project')} /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {gid('target-' + emb)};\n\t\t\tremoteInfo = {emb};\n\t\t}};")
    for test, host in tests:
        w(f"\t\t{gid('proxy-' + test)} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {gid('project')} /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {gid('target-' + host)};\n\t\t\tremoteInfo = {host};\n\t\t}};")
    w("/* End PBXContainerItemProxy section */\n")

    w("/* Begin PBXCopyFilesBuildPhase section */")
    for host, emb, name, spec_, path, _only in embeds:
        prod = [t for t in targets if t[0] == emb][0][1]
        w(f"\t\t{gid('copy-' + emb)} /* {name} */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = {q(path)};\n\t\t\tdstSubfolderSpec = {spec_};\n\t\t\tfiles = (\n\t\t\t\t{gid('bf-' + emb)} /* {prod} in {name} */,\n\t\t\t);\n\t\t\tname = {q(name)};\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
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

    if exceptions:
        w("/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */")
        for group, target, files in exceptions:
            listed = "".join(f"\t\t\t\t{q(f)},\n" for f in files)
            w(f"\t\t{gid('exc-' + group + target)} /* Exceptions for \"{group}\" folder in \"{target}\" target */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n\t\t\tmembershipExceptions = (\n{listed}\t\t\t);\n\t\t\ttarget = {gid('target-' + target)} /* {target} */;\n\t\t}};")
        w("/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */\n")

    w("/* Begin PBXFileSystemSynchronizedRootGroup section */")
    for g in groups:
        own = [e for e in exceptions if e[0] == g]
        exc = ""
        if own:
            listed = "".join(f"\t\t\t\t{gid('exc-' + e[0] + e[1])} /* Exceptions for \"{e[0]}\" folder in \"{e[1]}\" target */,\n" for e in own)
            exc = f"\t\t\texceptions = (\n{listed}\t\t\t);\n"
        w(f"\t\t{gid('group-' + g)} /* {g} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n{exc}\t\t\tpath = {q(g)};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
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
        for test, host in tests:
            if test == name:
                deps += f"\t\t\t\t{gid('dep-' + test)} /* PBXTargetDependency */,\n"
        syn = "".join(f"\t\t\t\t{gid('group-' + g)} /* {g} */,\n" for g in sorted(tgroups, key=lambda g: gid('group-' + g)))
        pdeps = "".join(f"\t\t\t\t{gid('pdep-' + name + pkg)} /* {pkg} */,\n" for pkg in pkgs)
        w(f"\t\t{gid('target-' + name)} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {gid('cl-' + name)} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n\t\t\tbuildPhases = (\n{phase_lines}\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{deps}\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n{syn}\t\t\t);\n\t\t\tname = {name};\n\t\t\tpackageProductDependencies = (\n{pdeps}\t\t\t);\n\t\t\tproductName = {name};\n\t\t\tproductReference = {gid('prod-' + name)} /* {prod} */;\n\t\t\tproductType = {q(ptype)};\n\t\t}};")
    w("/* End PBXNativeTarget section */\n")

    w("/* Begin PBXProject section */")
    hosts = dict(tests)
    attrs = "".join(
        f"\t\t\t\t\t{gid('target-' + t[0])} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n"
        + (f"\t\t\t\t\t\tTestTargetID = {gid('target-' + hosts[t[0]])};\n" if t[0] in hosts else "")
        + "\t\t\t\t\t};\n"
        for t in sorted(targets, key=lambda t: gid('target-' + t[0])))
    tlist = "".join(f"\t\t\t\t{gid('target-' + t[0])} /* {t[0]} */,\n" for t in targets)
    prefs = "".join(f"\t\t\t\t{gid('pkg-' + p)} /* XCLocalSwiftPackageReference \"../../Packages/{p}\" */,\n" for p in packages)
    w(f"\t\t{gid('project')} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2700;\n\t\t\t\tLastUpgradeCheck = 2700;\n\t\t\t\tTargetAttributes = {{\n{attrs}\t\t\t\t}};\n\t\t\t}};\n\t\t\tbuildConfigurationList = {gid('cl-project')} /* Build configuration list for PBXProject \"{app_name}\" */;\n\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n\t\t\tmainGroup = {gid('main')};\n\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpackageReferences = (\n{prefs}\t\t\t);\n\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {gid('products')} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n{tlist}\t\t\t);\n\t\t}};")
    w("/* End PBXProject section */\n")

    for section, prefix in [("PBXResourcesBuildPhase", "res"), ("PBXSourcesBuildPhase", "src")]:
        w(f"/* Begin {section} section */")
        for name, *_ in targets:
            label = "Resources" if prefix == "res" else "Sources"
            w(f"\t\t{gid(prefix + '-' + name)} /* {label} */ = {{\n\t\t\tisa = {section};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
        w(f"/* End {section} section */\n")

    w("/* Begin PBXTargetDependency section */")
    for host, emb, *_rest in embeds:
        only = f"\t\t\tplatformFilter = {_rest[-1]};\n" if _rest[-1] else ""
        w(f"\t\t{gid('dep-' + emb)} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n{only}\t\t\ttarget = {gid('target-' + emb)} /* {emb} */;\n\t\t\ttargetProxy = {gid('proxy-' + emb)} /* PBXContainerItemProxy */;\n\t\t}};")
    for test, host in tests:
        w(f"\t\t{gid('dep-' + test)} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {gid('target-' + host)} /* {host} */;\n\t\t\ttargetProxy = {gid('proxy-' + test)} /* PBXContainerItemProxy */;\n\t\t}};")
    w("/* End PBXTargetDependency section */\n")

    w("/* Begin XCBuildConfiguration section */")

    def config(key, name, settings):
        w(f"\t\t{gid(key)} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings_block(settings)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};")

    config("cfg-project-Debug", "Debug", project_debug)
    config("cfg-project-Release", "Release", project_release)
    for name, prod, ptype, ftype, settings, *_ in targets:
        settings = dict(settings, MARKETING_VERSION=VERSIONS[app_name])
        config(f"cfg-{name}-Debug", "Debug", settings)
        config(f"cfg-{name}-Release", "Release", settings)
    w("/* End XCBuildConfiguration section */\n")

    w("/* Begin XCConfigurationList section */")
    for key, label in [("project", f'PBXProject "{app_name}"')] + [(t[0], f'PBXNativeTarget "{t[0]}"') for t in targets]:
        w(f"\t\t{gid('cl-' + key)} /* Build configuration list for {label} */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{gid(f'cfg-{key}-Debug')} /* Debug */,\n\t\t\t\t{gid(f'cfg-{key}-Release')} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};")
    w("/* End XCConfigurationList section */\n")

    w("/* Begin XCLocalSwiftPackageReference section */")
    for p in packages:
        w(f"\t\t{gid('pkg-' + p)} /* XCLocalSwiftPackageReference \"../../Packages/{p}\" */ = {{\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = ../../Packages/{p};\n\t\t}};")
    w("/* End XCLocalSwiftPackageReference section */\n")

    w("/* Begin XCSwiftPackageProductDependency section */")
    for name, *_rest in targets:
        for pkg in _rest[-1]:
            w(f"\t\t{gid('pdep-' + name + pkg)} /* {pkg} */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = {gid('pkg-' + pkg)} /* XCLocalSwiftPackageReference \"../../Packages/{pkg}\" */;\n\t\t\tproductName = {pkg};\n\t\t}};")
    w("/* End XCSwiftPackageProductDependency section */")

    w(f"\t}};\n\trootObject = {gid('project')} /* Project object */;\n}}\n")

    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "project.pbxproj"), "w") as f:
        f.write(canonical("\n".join(P)))

    container = f"container:{app_name}.xcodeproj"

    def test_plan(plan, tests):
        def ref(target):
            return {"containerPath": f"container:{app_name}.xcodeproj", "identifier": gid("target-" + target), "name": target}
        # English and the US region, so tests can match on-screen words and units.
        options = {"targetForVariableExpansion": ref(app_name), "language": "en", "region": "US"}
        if plan.endswith("UI"):
            # UI tests drive a real simulator, where a slow frame can fail a good run: retry once before failing.
            options.update({"testRepetitionMode": "retryOnFailure", "maximumTestRepetitions": 2})
        else:
            options["codeCoverage"] = True
        # Stadig Macro's app tests are nearly all on the main actor, so running them together gains
        # nothing: they queue for it with each one's clock already running, and a wait or the time
        # allowance runs out behind the rest of the suite. One at a time took its 293 from 133 s and
        # 45 timeouts to 19 s.
        one_at_a_time = {"parallelizable": False} if app_name == "MacroTrack" and not plan.endswith("UI") else {}
        # A hung test fails on its own instead of holding the CI machine until the job's timeout.
        options.update({"testTimeoutsEnabled": True, "defaultTestExecutionTimeAllowance": 300 if plan.endswith("UI") else 120})
        return {
            "configurations": [{"id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"{app_name}/{plan}")).upper(), "name": "Default", "options": {}}],
            "defaultOptions": options,
            "testTargets": [{"target": ref(t), **one_at_a_time} for t in tests],
            "version": 1,
        }

    for plan, tests in test_plans:
        with open(os.path.join(ROOT, "Apps", app_name, f"{plan}.xctestplan"), "w") as f:
            f.write(json.dumps(test_plan(plan, tests), indent=2, sort_keys=True) + "\n")

    def scheme(target, buildable, launch_storekit=False):
        build_entries = f"""         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{gid('target-' + target)}" BuildableName = "{buildable}" BlueprintName = "{target}" ReferencedContainer = "{container}"></BuildableReference>
         </BuildActionEntry>
"""
        storekit = f"""      <StoreKitConfigurationFileReference identifier = "../../{app_name}.storekit"></StoreKitConfigurationFileReference>
""" if launch_storekit else ""
        # The app's scheme tests through its plans, the first being the default.
        plans = test_plans if target == app_name else []
        plan_refs = "".join(
            f"""         <TestPlanReference reference = "container:{p}.xctestplan"{' default = "YES"' if i == 0 else ''}></TestPlanReference>
""" for i, (p, *_) in enumerate(plans))
        test_body = f""">
      <TestPlans>
{plan_refs}      </TestPlans>
   </TestAction>""" if plans else "></TestAction>"
        return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2700" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
{build_entries}      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES"{test_body}
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{gid('target-' + target)}" BuildableName = "{buildable}" BlueprintName = "{target}" ReferencedContainer = "{container}"></BuildableReference>
      </BuildableProductRunnable>
{storekit}   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{gid('target-' + target)}" BuildableName = "{buildable}" BlueprintName = "{target}" ReferencedContainer = "{container}"></BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""

    schemes = os.path.join(out, "xcshareddata", "xcschemes")
    os.makedirs(schemes, exist_ok=True)
    for scheme_name, target, buildable, storekit in spec["schemes"]:
        with open(os.path.join(schemes, f"{scheme_name}.xcscheme"), "w") as f:
            f.write(scheme(target, buildable, launch_storekit=storekit))
    print("Wrote", out)


if __name__ == "__main__":
    # --packages <App> prints the local packages an app links, for scripts that test just those.
    if sys.argv[1:2] == ["--packages"]:
        print(" ".join(APPS[sys.argv[2]]["packages"]))
        sys.exit(0)
    names = sys.argv[1:] or list(APPS)
    for n in names:
        if n not in APPS:
            sys.exit(f"Unknown app {n}; choose from {', '.join(APPS)}")
        generate(APPS[n])
