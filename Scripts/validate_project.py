#!/usr/bin/env python3
"""Static validation for the Between us Xcode source package."""

from __future__ import annotations

import hashlib
import json
import plistlib
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "BetweenUs"
PROJECT = ROOT / "BetweenUs.xcodeproj" / "project.pbxproj"
SCHEME = ROOT / "BetweenUs.xcodeproj" / "xcshareddata" / "xcschemes" / "BetweenUs.xcscheme"


def fail(message: str) -> None:
    raise RuntimeError(message)


def parse_plist(path: Path) -> dict:
    with path.open("rb") as handle:
        value = plistlib.load(handle)
    if not isinstance(value, dict):
        fail(f"{path.relative_to(ROOT)} is not a plist dictionary")
    return value


def png_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    if len(data) != 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        fail(f"{path.relative_to(ROOT)} is not a valid PNG")
    return struct.unpack(">II", data[16:24])


def main() -> int:
    info = parse_plist(APP / "Info.plist")
    entitlements = parse_plist(APP / "BetweenUs.entitlements")
    privacy = parse_plist(APP / "PrivacyInfo.xcprivacy")

    if info.get("CFBundleShortVersionString") != "$(MARKETING_VERSION)":
        fail("Info.plist version is not build-setting driven")
    if info.get("CFBundleDisplayName") != "耳语":
        fail("Chinese display name must remain 耳语")
    if info.get("CKSharingSupported") is not True:
        fail("CKSharingSupported is missing")
    if "remote-notification" not in info.get("UIBackgroundModes", []):
        fail("remote-notification background mode is missing")
    if "CloudKit" not in entitlements.get("com.apple.developer.icloud-services", []):
        fail("CloudKit entitlement is missing")
    if privacy.get("NSPrivacyTracking") is not False:
        fail("Privacy manifest tracking value is unexpected")

    for path in (APP / "Assets.xcassets").rglob("Contents.json"):
        json.loads(path.read_text(encoding="utf-8"))

    icon = APP / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
    if png_dimensions(icon) != (1024, 1024):
        fail("App icon must be 1024 x 1024")

    ET.parse(SCHEME)
    pbx = PROJECT.read_text(encoding="utf-8")
    swift_files = sorted((APP).rglob("*.swift"))
    missing = [str(path.relative_to(ROOT)) for path in swift_files if path.name not in pbx]
    if missing:
        fail(f"Swift files missing from Xcode project: {missing}")

    sources_match = re.search(
        r"/\* Begin PBXSourcesBuildPhase section \*/(.*?)/\* End PBXSourcesBuildPhase section \*/",
        pbx,
        flags=re.DOTALL,
    )
    if not sources_match:
        fail("PBXSourcesBuildPhase section is missing")
    sources_block = sources_match.group(1)
    bad_source_counts = {
        path.name: len(re.findall(rf"/\* {re.escape(path.name)} in Sources \*/", sources_block))
        for path in swift_files
        if len(re.findall(rf"/\* {re.escape(path.name)} in Sources \*/", sources_block)) != 1
    }
    if bad_source_counts:
        fail(f"Swift source build-phase counts are invalid: {bad_source_counts}")
    if (APP / "Views" / "ContainerCard.swift").exists() or "ContainerCard.swift" in pbx:
        fail("Obsolete ContainerCard implementation is still present")

    marketing_match = re.search(r"MARKETING_VERSION = ([0-9][0-9.]*);", pbx)
    build_match = re.search(r"CURRENT_PROJECT_VERSION = ([0-9]+);", pbx)
    if marketing_match is None:
        fail("MARKETING_VERSION is missing from the Xcode project")
    if build_match is None:
        fail("CURRENT_PROJECT_VERSION is missing from the Xcode project")
    marketing_version = marketing_match.group(1)
    build_number = build_match.group(1)

    # 版本号以工程为准，README、CHANGELOG 与官网必须跟着它走，任何一处不同步都算失败。
    release = json.loads((ROOT / "website" / "release.json").read_text(encoding="utf-8"))
    if release.get("latestVersion") != marketing_version:
        fail(
            f"website/release.json latestVersion {release.get('latestVersion')!r} "
            f"does not match the project version {marketing_version!r}"
        )
    readme_text = (ROOT / "README.md").read_text(encoding="utf-8")
    if f"`{marketing_version}`" not in readme_text:
        fail(f"README.md does not state the project version {marketing_version}")
    if f"构建号为 `{build_number}`" not in readme_text:
        fail(f"README.md does not state the build number {build_number}")
    changelog_text = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    if not re.search(
        rf"^## {re.escape(marketing_version)} \({re.escape(build_number)}\)",
        changelog_text,
        flags=re.MULTILINE,
    ):
        fail(f"CHANGELOG.md has no entry for {marketing_version} ({build_number})")
    if 'PRODUCT_NAME = "Between us";' not in pbx:
        fail("English product name is not Between us")
    if 'BuildableName="Between us.app"' not in SCHEME.read_text(encoding="utf-8"):
        fail("Scheme product name is not Between us.app")
    if "IPHONEOS_DEPLOYMENT_TARGET = 17.0;" not in pbx:
        fail("Deployment target is not iOS 17.0")

    source_text = "\n".join(path.read_text(encoding="utf-8") for path in swift_files)
    view_text = "\n".join(path.read_text(encoding="utf-8") for path in (APP / "Views").rglob("*.swift"))
    required_interactions = [
        "VoiceHoldRecorderView",
        "cancelDistance",
        "formattedRecordingDuration",
        "RitualActionToken",
        "HoldToOpenControl",
        "fullScreenCover",
        "preparePermission",
        "isVoiceInteractionLocked",
        "scrollDismissesKeyboard",
        'accessibilityAction(named: Text("开始录音"))',
        "AVAudioSession.interruptionNotification",
        "UIApplication.didEnterBackgroundNotification",
    ]
    missing_interactions = [token for token in required_interactions if token not in source_text]
    if missing_interactions:
        fail(f"Core interaction implementation is incomplete: {missing_interactions}")
    forbidden_ui = [".confirmationDialog(", ".alert(", "Picker(\"筛选\""]
    found_ui = [token for token in forbidden_ui if token in view_text]
    if found_ui:
        fail(f"Traditional core UI patterns remain in Views: {found_ui}")

    forbidden = ["betweenUsCloudKitPushReceived", "TODO:", "FIXME:", "松开发送"]
    found = [token for token in forbidden if token in source_text]
    if found:
        fail(f"Stale source markers found: {found}")

    swiftc = subprocess.run(
        ["bash", "-lc", "command -v swiftc || true"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if swiftc:
        command = [swiftc, "-parse", *map(str, swift_files)]
        subprocess.run(command, cwd=ROOT, check=True)

    # build/ 与缓存目录是本地生成物，不计入空文件检查。
    generated_directories = {".git", "build", "DerivedData", ".derivedData", "xcuserdata", "__pycache__"}
    empty_files = [
        str(path.relative_to(ROOT))
        for path in ROOT.rglob("*")
        if path.is_file()
        and path.stat().st_size == 0
        and not generated_directories.intersection(path.relative_to(ROOT).parts)
    ]
    if empty_files:
        fail(f"Empty files found: {empty_files}")

    # 整包哈希清单是可选的：仓库当前不维护 FILE_MANIFEST.sha256，存在时才校验。
    manifest = ROOT / "FILE_MANIFEST.sha256"
    manifest_entries: dict[str, str] = {}
    if manifest.exists():
        for line_number, raw_line in enumerate(manifest.read_text(encoding="utf-8").splitlines(), start=1):
            if not raw_line.strip():
                continue
            match = re.fullmatch(r"([0-9a-f]{64})  \./(.+)", raw_line)
            if not match:
                fail(f"Malformed manifest line {line_number}")
            digest, relative_path = match.groups()
            if relative_path in manifest_entries:
                fail(f"Duplicate manifest entry: {relative_path}")
            manifest_entries[relative_path] = digest

        package_files = sorted(
            path for path in ROOT.rglob("*")
            if path.is_file()
            and path != manifest
            and ".git" not in path.parts
            and "xcuserdata" not in path.parts
            and "__pycache__" not in path.parts
            and path.suffix not in {".pyc", ".xcuserstate"}
            and path.name != ".DS_Store"
        )
        expected_paths = {str(path.relative_to(ROOT)) for path in package_files}
        actual_paths = set(manifest_entries)
        if expected_paths != actual_paths:
            fail(
                "Manifest file set is stale: "
                f"missing={sorted(expected_paths - actual_paths)}, extra={sorted(actual_paths - expected_paths)}"
            )
        bad_hashes = []
        for path in package_files:
            relative_path = str(path.relative_to(ROOT))
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if manifest_entries[relative_path] != digest:
                bad_hashes.append(relative_path)
        if bad_hashes:
            fail(f"Manifest hashes are stale: {bad_hashes}")

    manifest_summary = (
        f"and {len(manifest_entries)} manifest entries validated"
        if manifest_entries
        else "(no FILE_MANIFEST.sha256 in tree, package integrity check skipped)"
    )
    print(
        f"OK: {len(swift_files)} Swift files, plists, assets, scheme, project references "
        f"{manifest_summary}."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
