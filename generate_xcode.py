#!/usr/bin/env python3
import os, uuid, pathlib

PROJECT = "TaskWidget"
APP_TARGET = "TaskWidget"
WIDGET_TARGET = "TaskWidgetExtension"

def genUUID(): return str(uuid.uuid4()).upper().replace('-','')[:24]

def write_pbxproj(project_dir):
    app_files = [
        ("TaskWidgetApp.swift", "TaskWidget"),
        ("ContentView.swift", "TaskWidget"),
        ("Models/Task.swift", "TaskWidget/Models"),
        ("Services/APIClient.swift", "TaskWidget/Services"),
    ]
    widget_files = [
        ("TaskProvider.swift", "TaskWidgetExtension"),
        ("TaskWidgetView.swift", "TaskWidgetExtension"),
        ("AppIntent.swift", "TaskWidgetExtension"),
    ]
    shared_files = [
        ("Constants.swift", "Shared"),
    ]

    refs = {}
    for f, group in app_files + widget_files + shared_files:
        refs[f] = (genUUID(), genUUID())  # (fileRef, buildFile)

    app_group = genUUID()
    widget_group = genUUID()
    shared_group = genUUID()
    main_group = genUUID()

    app_target_id = genUUID()
    widget_target_id = genUUID()
    project_id = genUUID()

    pbx = f"""// !$*UTF8*$!
{{
    archiveVersion = 1;
    classes = {{
    }};
    objectVersion = 60;
    objects = {{

/* Begin PBXBuildFile section */
"""
    for f, g in app_files + widget_files + shared_files:
        pbx += f"        {refs[f][1]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {refs[f][0]} /* {f} */; }};\n"

    pbx += """/* End PBXBuildFile section */

/* Begin PBXFileReference section */
"""
    for f, g in app_files + widget_files + shared_files:
        pbx += f'        {refs[f][0]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{f.split("/")[-1]}"; sourceTree = "<group>"; }};\n'

    pbx += f"""        {genUUID()} /* {APP_TARGET}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP_TARGET}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
        {genUUID()} /* {WIDGET_TARGET}.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = {WIDGET_TARGET}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
        {genUUID()} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXGroup section */
        {main_group} /* Main */ = {{
            isa = PBXGroup;
            children = (
                {app_group} /* TaskWidget */,
                {widget_group} /* TaskWidgetExtension */,
                {shared_group} /* Shared */,
            );
            sourceTree = "<group>";
        }};
        {app_group} /* TaskWidget */ = {{
            isa = PBXGroup;
            children = (
"""
    for f, g in app_files:
        if "/" not in f:
            pbx += f"                {refs[f][0]} /* {f} */,\n"
    pbx += """            );
            path = TaskWidget;
            sourceTree = "<group>";
        };
"""
    pbx += f"""        {widget_group} /* TaskWidgetExtension */ = {{
            isa = PBXGroup;
            children = (
"""
    for f, g in widget_files:
        pbx += f"                {refs[f][0]} /* {f} */,\n"
    pbx += """            );
            path = TaskWidgetExtension;
            sourceTree = "<group>";
        };
"""
    pbx += f"""        {shared_group} /* Shared */ = {{
            isa = PBXGroup;
            children = (
"""
    for f, g in shared_files:
        pbx += f"                {refs[f][0]} /* {f} */,\n"
    pbx += """            );
            path = Shared;
            sourceTree = "<group>";
        };
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
        {app_target_id} /* TaskWidget */ = {{
            isa = PBXNativeTarget;
            buildConfigurationList = {genUUID()};
            buildPhases = (
                {genUUID()} /* Sources */,
            );
            buildRules = (
            );
            dependencies = (
            );
            name = TaskWidget;
            productName = TaskWidget;
            productType = "com.apple.product-type.application";
        }};
        {widget_target_id} /* TaskWidgetExtension */ = {{
            isa = PBXNativeTarget;
            buildConfigurationList = {genUUID()};
            buildPhases = (
                {genUUID()} /* Sources */,
            );
            buildRules = (
            );
            dependencies = (
            );
            name = TaskWidgetExtension;
            productName = TaskWidgetExtension;
            productType = "com.apple.product-type.app-extension";
        }};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
        {project_id} /* Project object */ = {{
            isa = PBXProject;
            attributes = {{
                BuildIndependentTargetsInParallel = 1;
            }};
            buildConfigurationList = {genUUID()};
            mainGroup = {main_group};
            productRefGroup = {main_group};
            projectDirPath = "";
            projectRoot = "";
            targets = (
                {app_target_id},
                {widget_target_id},
            );
        }};
/* End PBXProject section */

    }};
    rootObject = {project_id};
}}
"""
    proj_dir = os.path.join(project_dir, f"{PROJECT}.xcodeproj")
    os.makedirs(proj_dir, exist_ok=True)
    with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
        f.write(pbx)
    print(f"Created {proj_dir}/project.pbxproj")

if __name__ == "__main__":
    write_pbxproj(os.getcwd())
