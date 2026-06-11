import re
import sys

with open('AirBender.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# 1. Add C100000002
content = content.replace(
    'C100000001 /* com.airbender.helper in CopyFiles */ = {isa = PBXBuildFile; fileRef = E200000002 /* com.airbender.helper */; settings = {ATTRIBUTES = (CodeSignOnCopy, ); }; };',
    'C100000001 /* com.airbender.helper in CopyFiles */ = {isa = PBXBuildFile; fileRef = E200000002 /* com.airbender.helper */; settings = {ATTRIBUTES = (CodeSignOnCopy, ); }; };\n\t\tC100000002 /* com.airbender.helper.plist in CopyFiles */ = {isa = PBXBuildFile; fileRef = F100000017 /* com.airbender.helper.plist */; };'
)

# 2. Update D100000001 and Add D100000002
old_d1 = """		D100000001 /* Copy Helper */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = Contents/Library/LaunchServices;
			dstSubfolderSpec = 1;
			files = (
				C100000001 /* com.airbender.helper in CopyFiles */,
			);
			name = "Copy Helper";
			runOnlyForDeploymentPostprocessing = 0;
		};"""
new_d1 = """		D100000001 /* Copy Helper */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 6;
			files = (
				C100000001 /* com.airbender.helper in CopyFiles */,
			);
			name = "Copy Helper";
			runOnlyForDeploymentPostprocessing = 0;
		};
		D100000002 /* Copy Launch Daemon Plist */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = Contents/Library/LaunchDaemons;
			dstSubfolderSpec = 1;
			files = (
				C100000002 /* com.airbender.helper.plist in CopyFiles */,
			);
			name = "Copy Launch Daemon Plist";
			runOnlyForDeploymentPostprocessing = 0;
		};"""
content = content.replace(old_d1, new_d1)

# 3. Add D100000002 to build phases
old_build_phases = """			buildPhases = (
				E500000001 /* Sources (App) */,
				E300000001 /* Frameworks (App) */,
				E600000001 /* Resources (App) */,
				D100000001 /* Copy Helper */,
			);"""
new_build_phases = """			buildPhases = (
				E500000001 /* Sources (App) */,
				E300000001 /* Frameworks (App) */,
				E600000001 /* Resources (App) */,
				D100000001 /* Copy Helper */,
				D100000002 /* Copy Launch Daemon Plist */,
			);"""
content = content.replace(old_build_phases, new_build_phases)

# 4. Remove OTHER_LDFLAGS block from helper targets
ldflags_regex = re.compile(r'\t\t\t\tOTHER_LDFLAGS = \(\n\t\t\t\t\t"-sectcreate",\n\t\t\t\t\t__TEXT,\n\t\t\t\t\t__launchd_plist,\n\t\t\t\t\t"\$\(SRCROOT\)/com\.airbender\.helper/com\.airbender\.helper\.plist",\n\t\t\t\t\);\n')
content = ldflags_regex.sub('', content)

with open('AirBender.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print("Project file updated successfully.")
