#!/usr/bin/env python3
"""Regenerate TaskWidget.xcodeproj/project.pbxproj with complete, parseable content."""
import os, uuid

APP = "TaskWidget"
WIDGET = "TaskWidgetExtension"

def u():
    return uuid.uuid4().hex[:24].upper()

def rel(name):
    """Repo-relative path for a source entry."""
    if name.startswith("Shared/"):
        return name
    if name.startswith("TaskWidgetExtension/"):
        return name
    # Widget extension sources: names in WIDGET_SOURCES have no dir prefix
    if name in WIDGET_SOURCES:
        return f"{WIDGET}/{name}"
    return f"{APP}/{name}"

# Object ids
proj_id         = u()
main_group      = u()
products_group  = u()
app_group       = u()
widget_group    = u()
shared_group    = u()
app_target      = u()
widget_target   = u()
app_product_ref = u()
widget_product_ref = u()
app_sources_phase    = u()
widget_sources_phase = u()
app_resources_phase  = u()
widget_resources_phase = u()
app_frameworks_phase = u()
widget_frameworks_phase = u()
app_cfg_list    = u()
widget_cfg_list = u()
proj_cfg_list   = u()
app_cfg_debug   = u()
app_cfg_release = u()
widget_cfg_debug   = u()
widget_cfg_release = u()
proj_cfg_debug  = u()
proj_cfg_release = u()
app_dep     = u()
widget_dep  = u()
container_proxy = u()

APP_SOURCES = ["TaskWidgetApp.swift", "ContentView.swift", "Models/Task.swift", "Services/APIClient.swift"]
WIDGET_SOURCES = ["TaskProvider.swift", "TaskWidgetView.swift", "AppIntent.swift"]
SHARED = ["Shared/Constants.swift"]

def file_ref(name):
    return f"{u()} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{name.split('/')[-1]}\"; sourceTree = \"<group>\"; }};"

def build_file(name, ref):
    return f"{u()} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref}; }};"

# Build file + file ref maps
bf, fr = {}, {}
for n in APP_SOURCES:    fr[n] = u(); bf[n] = u()
for n in WIDGET_SOURCES: fr[n] = u(); bf[n] = u()
for n in SHARED:         fr[n] = u(); bf[n] = u()

info_plist_ref = u()

lines = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {")
lines.append("\t};")
lines.append("\tobjectVersion = 56;")
lines.append("\tobjects = {")

# PBXBuildFile
lines.append("")
lines.append("/* Begin PBXBuildFile section */")
for n in APP_SOURCES + WIDGET_SOURCES + SHARED:
    lines.append(f"\t\t{bf[n]} /* {n} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr[n]} /* {n} */; }};")
lines.append("/* End PBXBuildFile section */")

# PBXContainerItemProxy
lines.append("")
lines.append("/* Begin PBXContainerItemProxy section */")
lines.append(f"\t\t{container_proxy} /* PBXContainerItemProxy */ = {{")
lines.append("\t\t\tisa = PBXContainerItemProxy;")
lines.append(f"\t\t\tcontainerPortal = {proj_id} /* Project object */;")
lines.append("\t\t\tproxyType = 1;")
lines.append(f"\t\t\tremoteGlobalIDString = {widget_target};")
lines.append(f"\t\t\tremoteInfo = {WIDGET};")
lines.append("\t\t};")
lines.append("/* End PBXContainerItemProxy section */")

# PBXFileReference
lines.append("")
lines.append("/* Begin PBXFileReference section */")
for n in APP_SOURCES + WIDGET_SOURCES + SHARED:
    lines.append(f"\t\t{fr[n]} /* {n} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{rel(n)}\"; sourceTree = SOURCE_ROOT; }};")
lines.append(f"\t\t{app_product_ref} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
lines.append(f"\t\t{widget_product_ref} /* {WIDGET}.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = {WIDGET}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
lines.append(f"\t\t{info_plist_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = \"{WIDGET}/Info.plist\"; sourceTree = SOURCE_ROOT; }};")
lines.append("/* End PBXFileReference section */")

# PBXFrameworksBuildPhase
lines.append("")
lines.append("/* Begin PBXFrameworksBuildPhase section */")
for phase, nm in [(app_frameworks_phase, "TaskWidget"), (widget_frameworks_phase, "TaskWidgetExtension")]:
    lines.append(f"\t\t{phase} /* Frameworks */ = {{")
    lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
lines.append("/* End PBXFrameworksBuildPhase section */")

# PBXGroup
lines.append("")
lines.append("/* Begin PBXGroup section */")
lines.append(f"\t\t{main_group} = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{app_group} /* {APP} */,")
lines.append(f"\t\t\t\t{widget_group} /* {WIDGET} */,")
lines.append(f"\t\t\t\t{shared_group} /* Shared */,")
lines.append(f"\t\t\t\t{products_group} /* Products */,")
lines.append("\t\t\t);")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append(f"\t\t{app_group} /* {APP} */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for n in APP_SOURCES:
    lines.append(f"\t\t\t\t{fr[n]} /* {n} */,")
lines.append("\t\t\t);")
# path removed (using SOURCE_ROOT)
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append(f"\t\t{widget_group} /* {WIDGET} */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for n in WIDGET_SOURCES:
    lines.append(f"\t\t\t\t{fr[n]} /* {n} */,")
lines.append(f"\t\t\t\t{info_plist_ref} /* Info.plist */,")
lines.append("\t\t\t);")
# path removed
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append(f"\t\t{shared_group} /* Shared */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for n in SHARED:
    lines.append(f"\t\t\t\t{fr[n]} /* {n} */,")
lines.append("\t\t\t);")
# path removed
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append(f"\t\t{products_group} /* Products */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append("\t\t\t\t{app_product_ref} /* {APP}.app */,".replace("{app_product_ref}", app_product_ref).replace("{APP}", APP))
lines.append("\t\t\t\t{widget_product_ref} /* {WIDGET}.appex */,".replace("{widget_product_ref}", widget_product_ref).replace("{WIDGET}", WIDGET))
lines.append("\t\t\t);")
lines.append("\t\t\tname = Products;")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append("/* End PBXGroup section */")

# PBXNativeTarget
lines.append("")
lines.append("/* Begin PBXNativeTarget section */")
lines.append(f"\t\t{app_target} /* {APP} */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append(f"\t\t\tbuildConfigurationList = {app_cfg_list} /* Build configuration list for PBXNativeTarget \"{APP}\" */;")
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{app_sources_phase} /* Sources */,")
lines.append(f"\t\t\t\t{app_frameworks_phase} /* Frameworks */,")
lines.append(f"\t\t\t\t{app_resources_phase} /* Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append("\t\t\t);")
lines.append(f"\t\t\tname = {APP};")
lines.append(f"\t\t\tproductName = {APP};")
lines.append(f"\t\t\tproductReference = {app_product_ref} /* {APP}.app */;")
lines.append("\t\t\tproductType = \"com.apple.product-type.application\";")
lines.append("\t\t};")
lines.append(f"\t\t{widget_target} /* {WIDGET} */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append(f"\t\t\tbuildConfigurationList = {widget_cfg_list} /* Build configuration list for PBXNativeTarget \"{WIDGET}\" */;")
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{widget_sources_phase} /* Sources */,")
lines.append(f"\t\t\t\t{widget_frameworks_phase} /* Frameworks */,")
lines.append(f"\t\t\t\t{widget_resources_phase} /* Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append("\t\t\t);")
lines.append(f"\t\t\tname = {WIDGET};")
lines.append(f"\t\t\tproductName = {WIDGET};")
lines.append(f"\t\t\tproductReference = {widget_product_ref} /* {WIDGET}.appex */;")
lines.append("\t\t\tproductType = \"com.apple.product-type.app-extension\";")
lines.append("\t\t};")
lines.append("/* End PBXNativeTarget section */")

# PBXProject
lines.append("")
lines.append("/* Begin PBXProject section */")
lines.append(f"\t\t{proj_id} /* Project object */ = {{")
lines.append("\t\t\tisa = PBXProject;")
lines.append("\t\t\tattributes = {")
lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
lines.append("\t\t\t\tLastSwiftUpdateCheck = 1600;")
lines.append("\t\t\t\tLastUpgradeCheck = 1600;")
lines.append("\t\t\t};")
lines.append(f"\t\t\tbuildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject \"{APP}\" */;")
lines.append("\t\t\tcompatibilityVersion = \"Xcode 15.0\";")
lines.append("\t\t\tdevelopmentRegion = en;")
lines.append("\t\t\thasScannedForEncodings = 0;")
lines.append("\t\t\tknownRegions = (")
lines.append("\t\t\t\ten,")
lines.append("\t\t\t\tBase,")
lines.append("\t\t\t);")
lines.append(f"\t\t\tmainGroup = {main_group};")
lines.append(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
lines.append("\t\t\tprojectDirPath = \"\";")
lines.append("\t\t\tprojectRoot = \"\";")
lines.append("\t\t\ttargets = (")
lines.append(f"\t\t\t\t{app_target} /* {APP} */,")
lines.append(f"\t\t\t\t{widget_target} /* {WIDGET} */,")
lines.append("\t\t\t);")
lines.append("\t\t};")
lines.append("/* End PBXProject section */")

# PBXResourcesBuildPhase
lines.append("")
lines.append("/* Begin PBXResourcesBuildPhase section */")
for phase, nm in [(app_resources_phase, APP), (widget_resources_phase, WIDGET)]:
    lines.append(f"\t\t{phase} /* Resources */ = {{")
    lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
lines.append("/* End PBXResourcesBuildPhase section */")

# PBXSourcesBuildPhase
lines.append("")
lines.append("/* Begin PBXSourcesBuildPhase section */")
lines.append(f"\t\t{app_sources_phase} /* Sources */ = {{")
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for n in APP_SOURCES + SHARED:
    lines.append(f"\t\t\t\t{bf[n]} /* {n} in Sources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append(f"\t\t{widget_sources_phase} /* Sources */ = {{")
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for n in WIDGET_SOURCES + SHARED + ["Models/Task.swift", "Services/APIClient.swift"]:
    lines.append(f"\t\t\t\t{bf[n]} /* {n} in Sources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */")

# XCBuildConfiguration
lines.append("")
lines.append("/* Begin XCBuildConfiguration section */")
def cfg(uuid, name, settings):
    out = [f"\t\t{uuid} /* {name} */ = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
    for k, v in settings.items():
        out.append(f"\t\t\t\t{k} = {v if v != '' else chr(34) + chr(34)};")
    out += ["\t\t\t};", f"\t\t\tname = {name};", "\t\t};"]
    return out

common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "MACOSX_DEPLOYMENT_TARGET": "13.0",
    "SDKROOT": "macosx",
    "SWIFT_VERSION": "5.0",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "CODE_SIGN_STYLE": "Automatic",
}
proj_settings_extra = {
    "ONLY_ACTIVE_ARCH": "YES",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": "\"-Onone\"",
    "GCC_PREPROCESSOR_DEFINITIONS": "(\"DEBUG=1\",\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t)",
}
lines += cfg(proj_cfg_debug, "Debug", {**common, **proj_settings_extra})
lines += cfg(proj_cfg_release, "Release", {**common, "SWIFT_COMPILATION_MODE": "wholemodule", "DEBUG_INFORMATION_FORMAT": "\"dwarf-with-dsym\""})

app_common = {
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_NSHumanReadableCopyright": "\"\"",
    "LD_RUNPATH_SEARCH_PATHS": "(\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t\t\"@executable_path/../Frameworks\",\n\t\t\t\t)",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.multiagent.taskwidget",
    "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
    "SDKROOT": "macosx",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "MACOSX_DEPLOYMENT_TARGET": "13.0",
}
lines += cfg(app_cfg_debug, "Debug", app_common)
lines += cfg(app_cfg_release, "Release", app_common)

widget_common = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "TaskWidgetExtension/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "TaskWidget",
    "INFOPLIST_KEY_NSHumanReadableCopyright": "\"\"",
    "LD_RUNPATH_SEARCH_PATHS": "(\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t\t\"@executable_path/../Frameworks\",\n\t\t\t\t\t\"@executable_path/../../../../Frameworks\",\n\t\t\t\t)",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.multiagent.taskwidget.extension",
    "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
    "SDKROOT": "macosx",
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "MACOSX_DEPLOYMENT_TARGET": "13.0",
}
lines += cfg(widget_cfg_debug, "Debug", widget_common)
lines += cfg(widget_cfg_release, "Release", widget_common)
lines.append("/* End XCBuildConfiguration section */")

# XCConfigurationList
lines.append("")
lines.append("/* Begin XCConfigurationList section */")
def cfg_list(uuid, label, dbg, rel):
    return [
        f"\t\t{uuid} /* Build configuration list for {label} */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        "\t\t\tbuildConfigurations = (",
        f"\t\t\t\t{dbg} /* Debug */,",
        f"\t\t\t\t{rel} /* Release */,",
        "\t\t\t);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
    ]
lines += cfg_list(proj_cfg_list, f'PBXProject "{APP}"', proj_cfg_debug, proj_cfg_release)
lines += cfg_list(app_cfg_list, f'PBXNativeTarget "{APP}"', app_cfg_debug, app_cfg_release)
lines += cfg_list(widget_cfg_list, f'PBXNativeTarget "{WIDGET}"', widget_cfg_debug, widget_cfg_release)
lines.append("/* End XCConfigurationList section */")

lines.append("\t};")
lines.append(f"\trootObject = {proj_id} /* Project object */;")
lines.append("}")

# Fix a few f-string placeholders that didn't interpolate
content = "\n".join(lines) + "\n"

proj_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), f"{APP}.xcodeproj")
os.makedirs(proj_dir, exist_ok=True)
with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
    f.write(content)
print(f"Wrote {proj_dir}/project.pbxproj ({len(content)} bytes)")
