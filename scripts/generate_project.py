"""Generate a dependency-free, deterministic Xcode project for the native iOS app."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "ios"
PROJECT = IOS / "QingJi.xcodeproj"


def uid(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()


def quoted(value):
    return json.dumps(value, ensure_ascii=False)


def generate():
    if sys.platform == "darwin":
        # Artwork is preserved; only normalize the app-icon build input to Apple's size.
        subprocess.run(["sips", "-z", "1024", "1024", str(IOS / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")], check=True, stdout=subprocess.DEVNULL)
        for icon in sorted((IOS / "App/Assets.xcassets").glob("Member*.appiconset/*.png")):
            subprocess.run(["sips", "-z", "1024", "1024", str(icon)], check=True, stdout=subprocess.DEVNULL)
    PROJECT.mkdir(exist_ok=True)
    sources = sorted([*IOS.glob("App/*.swift"), *IOS.glob("Core/*.swift")])
    resources = [IOS / "App/Assets.xcassets", IOS / "App/PrivacyInfo.xcprivacy"]
    objects = []

    def add(name, value):
        objects.append(f"\t\t{uid(name)} = {{ {value} }};")

    source_builds, resource_builds, children = [], [], []
    for path in sources + resources:
        relative = path.relative_to(IOS).as_posix()
        file_id, build_id = uid("file:" + relative), uid("build:" + relative)
        kind = "sourcecode.swift" if path.suffix == ".swift" else "folder.assetcatalog" if path.suffix == ".xcassets" else "text.xml"
        add("file:" + relative, f"isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(relative)}; sourceTree = SOURCE_ROOT;")
        add("build:" + relative, f"isa = PBXBuildFile; fileRef = {file_id};")
        children.append(file_id)
        (source_builds if path in sources else resource_builds).append(build_id)

    add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = QingJi.app; sourceTree = BUILT_PRODUCTS_DIR;')
    add("products", f'isa = PBXGroup; children = ({uid("product")},); name = Products; sourceTree = "<group>";')
    add("main", f'isa = PBXGroup; children = ({",".join(children + [uid("products")])},); sourceTree = "<group>";')
    for name, kind, files in [("sources", "PBXSourcesBuildPhase", source_builds), ("resources", "PBXResourcesBuildPhase", resource_builds), ("frameworks", "PBXFrameworksBuildPhase", [])]:
        add(name, f'isa = {kind}; buildActionMask = 2147483647; files = ({",".join(files)}{"," if files else ""}); runOnlyForDeploymentPostprocessing = 0;')

    add("target", f'''isa = PBXNativeTarget; buildConfigurationList = {uid("target-configs")};
        buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")},);
        buildRules = (); dependencies = (); name = QingJi; productName = QingJi;
        productReference = {uid("product")}; productType = "com.apple.product-type.application";''')
    add("ui-file", 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UITests/QingJiUITests.swift; sourceTree = SOURCE_ROOT;')
    add("ui-build", f'isa = PBXBuildFile; fileRef = {uid("ui-file")};')
    add("ui-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = QingJiUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    add("ui-sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("ui-build")},); runOnlyForDeploymentPostprocessing = 0;')
    add("ui-frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    add("ui-resources", 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    add("ui-proxy", f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target")}; remoteInfo = QingJi;')
    add("ui-dependency", f'isa = PBXTargetDependency; target = {uid("target")}; targetProxy = {uid("ui-proxy")};')
    add("ui-target", f'''isa = PBXNativeTarget; buildConfigurationList = {uid("ui-configs")};
        buildPhases = ({uid("ui-sources")},{uid("ui-frameworks")},{uid("ui-resources")},);
        buildRules = (); dependencies = ({uid("ui-dependency")},); name = QingJiUITests; productName = QingJiUITests;
        productReference = {uid("ui-product")}; productType = "com.apple.product-type.bundle.ui-testing";''')
    common = '''CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0;
        SWIFT_VERSION = 5.0; CLANG_ENABLE_OBJC_ARC = YES; ENABLE_USER_SCRIPT_SANDBOXING = YES;'''
    target = '''ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
        ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "Member01 Member02 Member03 Member04 Member05";
        CODE_SIGN_ENTITLEMENTS = App/QingJi.entitlements; "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]" = App/Simulator.entitlements; CODE_SIGN_STYLE = Automatic;
        CURRENT_PROJECT_VERSION = 13; MARKETING_VERSION = 0.10.1; GENERATE_INFOPLIST_FILE = NO;
        INFOPLIST_FILE = App/Info.plist; PRODUCT_BUNDLE_IDENTIFIER = com.cnalbin.qingji;
        PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1;
        SUPPORTS_MACCATALYST = NO; SWIFT_EMIT_LOC_STRINGS = YES;
        LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";'''
    for scope in ["project", "target", "ui"]:
        for configuration in ["Debug", "Release"]:
            settings = common + (target if scope == "target" else "")
            if scope == "ui":
                settings += ''' GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.cnalbin.qingji.uitests;
                    PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1; TEST_TARGET_NAME = QingJi; CODE_SIGN_STYLE = Automatic;'''
            settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if configuration == "Debug" else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; VALIDATE_PRODUCT = YES;'
            add(f"{scope}-{configuration}", f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {configuration};')
        add(f"{scope}-configs", f'isa = XCConfigurationList; buildConfigurations = ({uid(scope + "-Debug")},{uid(scope + "-Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    add("project", f'''isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; TargetAttributes = {{ {uid("target")} = {{ CreatedOnToolsVersion = 16.0; SystemCapabilities = {{ com.apple.HealthKit = {{ enabled = 1; }}; }}; }}; }}; }};
        buildConfigurationList = {uid("project-configs")}; compatibilityVersion = "Xcode 14.0";
        developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (zh_CN,en,Base,);
        mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = "";
        projectRoot = ""; targets = ({uid("target")},{uid("ui-target")},);''')
    content = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {uid("project")};\n}}\n'
    (PROJECT / "project.pbxproj").write_text(content, encoding="utf-8")
    schemes = PROJECT / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="QingJi.app" BlueprintName="QingJi" ReferencedContainer="container:QingJi.xcodeproj"/>'
    ui_reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("ui-target")}" BuildableName="QingJiUITests.xctest" BlueprintName="QingJiUITests" ReferencedContainer="container:QingJi.xcodeproj"/>'
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ui_reference}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
    (schemes / "QingJi.xcscheme").write_text(scheme, encoding="utf-8")
    print(f"Generated {len(sources)} Swift files into {PROJECT.name}")


if __name__ == "__main__":
    generate()
