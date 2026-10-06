#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 canonliuliang

"""Generate the checked-in Xcode project without third-party project generators."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--team", help="Apple development team ID; stored only in ignored local signing settings")
args = parser.parse_args()
private = ROOT / ".private"
private.mkdir(exist_ok=True, mode=0o700)
signing = private / "Signing.xcconfig"
if args.team is not None:
    if args.team and (len(args.team) != 10 or not args.team.isascii() or not args.team.isalnum()):
        parser.error("--team must be an empty string or a 10-character Apple team ID")
    signing.write_text(f"WRISTCHAT_DEVELOPMENT_TEAM = {args.team}\n")
elif not signing.exists():
    signing.write_text("WRISTCHAT_DEVELOPMENT_TEAM =\n")
signing.chmod(0o600)
objects = {}

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def add(identity, **fields):
    key = uid(identity)
    objects[key] = fields
    return key

def ref(path, file_type, source_tree="<group>"):
    return add("file:" + path, isa="PBXFileReference", lastKnownFileType=file_type,
               path=path, sourceTree=source_tree)

def phase(identity, isa, files, **extra):
    return add(identity, isa=isa, buildActionMask=2147483647, files=files,
               runOnlyForDeploymentPostprocessing=0, **extra)

swift_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "WatchChat").rglob("*.swift"))
source_refs = [ref(p, "sourcecode.swift") for p in swift_files]
source_build = [add("build:" + p, isa="PBXBuildFile", fileRef=r) for p, r in zip(swift_files, source_refs)]
resource_paths = [("WatchChat/Assets.xcassets", "folder.assetcatalog"),
                  (".private/BootstrapCredentials.plist", "text.plist.xml"),
                  ("LICENSE", "text"),
                  ("WatchChat/AppShortcuts.xcstrings", "text.json.xcstrings"),
                  ("WatchChat/PrivacyInfo.xcprivacy", "text.plist.xml")]
resource_refs = [ref(p, t) for p, t in resource_paths]
signing_ref = ref(".private/Signing.xcconfig", "text.xcconfig")
resources = [add("resource:" + p, isa="PBXBuildFile", fileRef=r)
             for (p, _), r in zip(resource_paths, resource_refs)]
watch_product = ref("WristChat.app", "wrapper.application", "BUILT_PRODUCTS_DIR")
widget_product = ref("WristChatWidgetsExtension.appex", "wrapper.app-extension", "BUILT_PRODUCTS_DIR")
container_product = ref("WristChatContainer.app", "wrapper.application", "BUILT_PRODUCTS_DIR")
products = add("products", isa="PBXGroup", children=[watch_product, widget_product, container_product], name="Products", sourceTree="<group>")
sources = add("sources", isa="PBXGroup", children=source_refs + resource_refs + [signing_ref, ref("WatchChat/Info.plist", "text.plist.xml")], name="WatchChat", sourceTree="<group>")
widget_source = ref("Widgets/WristChatWidgets.swift", "sourcecode.swift")
widget_info = ref("Widgets/Info.plist", "text.plist.xml")
widget_group = add("widget_group", isa="PBXGroup", children=[widget_source, widget_info], name="Widgets", sourceTree="<group>")
docs = add("docs", isa="PBXGroup", children=[ref("README.md", "net.daringfireball.markdown"),
    ref("Documentation/Design.md", "net.daringfireball.markdown")], name="Documentation", sourceTree="<group>")
main = add("main", isa="PBXGroup", children=[sources, widget_group, docs, products], sourceTree="<group>")

base = {
    "CLANG_ENABLE_MODULES": "YES", "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete",
    "SWIFT_EMIT_LOC_STRINGS": "YES", "CODE_SIGN_STYLE": "Automatic", "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": "1.8.1", "CURRENT_PROJECT_VERSION": "13", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "DEVELOPMENT_TEAM": "$(WRISTCHAT_DEVELOPMENT_TEAM)",
}
watch_settings = base | {
    "SDKROOT": "watchos", "SUPPORTED_PLATFORMS": "watchos watchsimulator", "WATCHOS_DEPLOYMENT_TARGET": "27.0",
    "TARGETED_DEVICE_FAMILY": "4", "PRODUCT_BUNDLE_IDENTIFIER": "com.liuliang.WristChat.watchkitapp",
    "PRODUCT_NAME": "WristChat", "INFOPLIST_KEY_CFBundleDisplayName": "腕聊",
    "INFOPLIST_FILE": "WatchChat/Info.plist",
    "CODE_SIGN_ENTITLEMENTS": "WatchChat/WristChat.entitlements",
    "INFOPLIST_KEY_WKApplication": "YES", "INFOPLIST_KEY_WKWatchOnly": "YES",
    "SKIP_INSTALL": "YES",
    "INFOPLIST_KEY_NSMicrophoneUsageDescription": "使用系统听写输入聊天问题。",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks", "ENABLE_PREVIEWS": "YES",
}
widget_settings = base | {
    "SDKROOT": "watchos", "SUPPORTED_PLATFORMS": "watchos watchsimulator", "WATCHOS_DEPLOYMENT_TARGET": "27.0",
    "TARGETED_DEVICE_FAMILY": "4", "PRODUCT_BUNDLE_IDENTIFIER": "com.liuliang.WristChat.watchkitapp.widgets",
    "PRODUCT_NAME": "WristChatWidgetsExtension", "INFOPLIST_KEY_CFBundleDisplayName": "腕聊",
    "INFOPLIST_FILE": "Widgets/Info.plist", "APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
}
container_settings = base | {
    "SDKROOT": "iphoneos", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "IPHONEOS_DEPLOYMENT_TARGET": "27.0", "TARGETED_DEVICE_FAMILY": "1,2",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.liuliang.WristChat", "PRODUCT_NAME": "WristChatContainer",
    "INFOPLIST_KEY_CFBundleDisplayName": "腕聊", "SKIP_INSTALL": "NO",
}

def configs(name, settings):
    entries = []
    for mode in ["Debug", "Release"]:
        extra = {"SWIFT_OPTIMIZATION_LEVEL": "-Onone", "DEBUG_INFORMATION_FORMAT": "dwarf",
                 "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)"} if mode == "Debug" else {
                 "SWIFT_OPTIMIZATION_LEVEL": "-O", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                 "VALIDATE_PRODUCT": "YES"}
        entries.append(add(name + mode, isa="XCBuildConfiguration", baseConfigurationReference=signing_ref,
                           buildSettings=settings | extra, name=mode))
    return add(name + "configs", isa="XCConfigurationList", buildConfigurations=entries,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

widget_target = add("widget_target", isa="PBXNativeTarget", buildConfigurationList=configs("widget", widget_settings),
    buildPhases=[phase("widget_swift_phase", "PBXSourcesBuildPhase", [
        add("widget_swift", isa="PBXBuildFile", fileRef=widget_source),
        add("widget_routes", isa="PBXBuildFile", fileRef=source_refs[swift_files.index("WatchChat/Core/WristChatRoute.swift")])]),
        phase("widget_framework_phase", "PBXFrameworksBuildPhase", []),
        phase("widget_resources_phase", "PBXResourcesBuildPhase", [
            add("widget_assets", isa="PBXBuildFile", fileRef=resource_refs[0]),
            add("widget_privacy", isa="PBXBuildFile", fileRef=resource_refs[2])])],
    buildRules=[], dependencies=[], name="WristChatWidgets", productName="WristChatWidgetsExtension",
    productReference=widget_product, productType="com.apple.product-type.app-extension")
widget_proxy = add("widget_proxy", isa="PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1,
    remoteGlobalIDString=widget_target, remoteInfo="WristChatWidgets")
widget_dependency = add("widget_dependency", isa="PBXTargetDependency", target=widget_target, targetProxy=widget_proxy)
widget_embed = add("widget_embed", isa="PBXBuildFile", fileRef=widget_product,
    settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
watch_target = add("watch_target", isa="PBXNativeTarget", buildConfigurationList=configs("watch", watch_settings),
    buildPhases=[phase("swift_phase", "PBXSourcesBuildPhase", source_build),
                 phase("framework_phase", "PBXFrameworksBuildPhase", []),
                 phase("resource_phase", "PBXResourcesBuildPhase", resources),
                 phase("embed_widgets", "PBXCopyFilesBuildPhase", [widget_embed], dstPath="", dstSubfolderSpec=13,
                       name="Embed App Extensions")],
    buildRules=[], dependencies=[widget_dependency], name="WristChat", productName="WristChat",
    productReference=watch_product, productType="com.apple.product-type.application")
proxy = add("watch_proxy", isa="PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1,
            remoteGlobalIDString=watch_target, remoteInfo="WristChat")
dependency = add("watch_dependency", isa="PBXTargetDependency", target=watch_target, targetProxy=proxy)
embed = add("watch_embed", isa="PBXBuildFile", fileRef=watch_product,
            settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
container_target = add("container_target", isa="PBXNativeTarget",
    buildConfigurationList=configs("container", container_settings), buildPhases=[
        phase("container_resources", "PBXResourcesBuildPhase", []),
        phase("embed_watch", "PBXCopyFilesBuildPhase", [embed], dstPath="$(CONTENTS_FOLDER_PATH)/Watch",
              dstSubfolderSpec=16, name="Embed Watch Content")],
    buildRules=[], dependencies=[dependency], name="WristChatContainer", productName="WristChatContainer",
    productReference=container_product, productType="com.apple.product-type.application.watchapp2-container")
project = add("project", isa="PBXProject", attributes={"LastUpgradeCheck": "2700",
    "LastSwiftUpdateCheck": "2700", "BuildIndependentTargetsInParallel": "YES",
    "TargetAttributes": {watch_target: {"CreatedOnToolsVersion": "27.0"},
                         container_target: {"CreatedOnToolsVersion": "27.0"},
                         widget_target: {"CreatedOnToolsVersion": "27.0"}}},
    buildConfigurationList=configs("project", {"CLANG_ENABLE_MODULES": "YES"}),
    compatibilityVersion="Xcode 15.0", developmentRegion="zh-Hans", hasScannedForEncodings=0,
    knownRegions=["zh-Hans", "en", "Base"], mainGroup=main, productRefGroup=products,
    projectDirPath="", projectRoot="", targets=[container_target, watch_target, widget_target])

def encode(value, level=0):
    if isinstance(value, dict):
        tab = "\t" * level
        return "{\n" + "".join(tab + "\t" + json.dumps(str(k), ensure_ascii=False) + " = " +
                    encode(v, level + 1) + ";\n" for k, v in value.items()) + tab + "}"
    if isinstance(value, list):
        return "(" + ", ".join(encode(v, level) for v in value) + ")"
    if isinstance(value, int): return str(value)
    return json.dumps(value, ensure_ascii=False)

project_dir = ROOT / "WristChat.xcodeproj"
project_dir.mkdir(exist_ok=True)
(project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1,
    "classes": {}, "objectVersion": 60, "objects": objects, "rootObject": project}) + "\n")
schemes = project_dir / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes / "WristChat.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{watch_target}" BuildableName="WristChat.app" BlueprintName="WristChat" ReferencedContainer="container:WristChat.xcodeproj"/>
  </BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{watch_target}" BuildableName="WristChat.app" BlueprintName="WristChat" ReferencedContainer="container:WristChat.xcodeproj"/></BuildableProductRunnable>
 </LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugServiceExtension="internal">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{watch_target}" BuildableName="WristChat.app" BlueprintName="WristChat" ReferencedContainer="container:WristChat.xcodeproj"/></BuildableProductRunnable>
 </ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')

# Allow a fresh source checkout to build without an embedded personal credential.
private = ROOT / ".private"
private.mkdir(exist_ok=True, mode=0o700)
credential = private / "BootstrapCredentials.plist"
if not credential.exists():
    credential.write_bytes(plistlib.dumps({"MiMoAPIKey": "", "DeepSeekAPIKey": ""}))
    credential.chmod(0o600)
print("Generated WristChat.xcodeproj")
