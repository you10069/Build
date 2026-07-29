#!/usr/bin/env python3
"""Prepare a customized CMFA checkout for an arm64-only Android build."""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path


GEO_FILES = ("geoip.metadb", "geosite.dat", "ASN.mmdb", "BundleMRS.7z")
OTHER_ABIS = ("armeabi-v7a", '"x86"', '"x86_64"')
APPLICATION_ID_PATTERN = re.compile(
    r"[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+"
)
CORE_VERSION_PATTERN = re.compile(
    r"(?:v[0-9][A-Za-z0-9._-]*|g[0-9a-f]{7,40})"
)


def read(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"Required source file is missing: {path}")
    return path.read_text(encoding="utf-8")


def write_if_changed(path: Path, old: str, new: str) -> None:
    if old != new:
        path.write_text(new, encoding="utf-8")
        print(f"patched: {path}")
    else:
        print(f"unchanged: {path}")


def remove_line_containing(text: str, needle: str) -> str:
    return "".join(line for line in text.splitlines(keepends=True) if needle not in line)


def block_span(text: str, marker: str, start: int = 0) -> tuple[int, int] | None:
    marker_at = text.find(marker, start)
    if marker_at < 0:
        return None

    marker_end = marker_at + len(marker)
    brace_at = text.find("{", marker_at, marker_end)
    if brace_at < 0:
        brace_at = text.find("{", marker_end)
    if brace_at < 0:
        raise SystemExit(f"Opening brace not found after marker: {marker}")

    depth = 0
    for index in range(brace_at, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                while end < len(text) and text[end] in "\r\n":
                    end += 1
                return marker_at, end

    raise SystemExit(f"Closing brace not found after marker: {marker}")


def remove_block(text: str, marker: str, required_content: str | None = None) -> str:
    search_at = 0
    while True:
        span = block_span(text, marker, search_at)
        if span is None:
            return text
        begin, end = span
        block = text[begin:end]
        if required_content is None or required_content in block:
            return text[:begin] + text[end:]
        search_at = end


def replace_function(text: str, marker: str, replacement: str) -> str:
    span = block_span(text, marker)
    if span is None:
        return text
    begin, end = span
    return text[:begin] + replacement + text[end:]


def parse_version(value: str) -> tuple[str, int]:
    version_name = value.removeprefix("v")
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version_name)
    if not match:
        raise SystemExit(
            f"VERSION must look like v2.11.32 or 2.11.32, received: {value}"
        )

    major, minor, patch = (int(part) for part in match.groups())
    version_code = int(f"{major}{minor:02d}{patch:03d}")
    return version_name, version_code


def make_app_version(
    source_version: str,
    base_version_code: int,
    build_revision: int,
    app_name: str,
    core_version: str,
) -> tuple[str, int]:
    if not 1 <= build_revision <= 99:
        raise SystemExit("BUILD_REVISION must be between 1 and 99")

    version_label = re.sub(r"[^A-Za-z0-9]+", "", app_name).upper()
    if not version_label:
        raise SystemExit("APP_NAME must contain a letter or number for version labeling")
    if not CORE_VERSION_PATTERN.fullmatch(core_version):
        raise SystemExit(
            "CORE_VERSION must look like v1.19.28, "
            f"v1.19.28-gabcdef0, or gabcdef0; received: {core_version}"
        )

    version_name = (
        f"{source_version}-{version_label}.{build_revision}+{core_version}"
    )
    version_code = base_version_code * 100 + build_revision
    if version_code > 2_100_000_000:
        raise SystemExit(f"Generated versionCode is too large: {version_code}")
    return version_name, version_code


def export_github_metadata(version_name: str, version_code: int) -> None:
    values = (
        ("APP_VERSION_NAME", version_name),
        ("APP_VERSION_CODE", str(version_code)),
    )
    github_env = os.environ.get("GITHUB_ENV")
    if github_env:
        with Path(github_env).open("a", encoding="utf-8") as output:
            for key, value in values:
                output.write(f"{key}={value}\n")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with Path(github_output).open("a", encoding="utf-8") as output:
            output.write(f"version_name={version_name}\n")
            output.write(f"version_code={version_code}\n")


def kotlin_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")


def patch_root_build(
    root: Path,
    version_name: str,
    version_code: int,
    app_name: str,
) -> None:
    path = root / "build.gradle.kts"
    old = read(path)
    new = old

    new, name_count = re.subn(
        r'versionName\s*=\s*"[^"]+"',
        f'versionName = "{version_name}"',
        new,
        count=1,
    )
    new, code_count = re.subn(
        r"versionCode\s*=\s*\d+",
        f"versionCode = {version_code}",
        new,
        count=1,
    )
    if name_count != 1 or code_count != 1:
        raise SystemExit("Could not update versionName/versionCode in build.gradle.kts")

    new = re.sub(
        r'abiFilters\s*\+=\s*listOf\([^\n]+\)',
        'abiFilters += listOf("arm64-v8a")',
        new,
    )
    new = re.sub(
        r'abiFilters\("arm64-v8a"[^\n]+\)',
        'abiFilters("arm64-v8a")',
        new,
    )
    new = re.sub(
        r'include\("arm64-v8a"[^\n]+\)',
        'include("arm64-v8a")',
        new,
    )
    new = new.replace("isUniversalApk = true", "isUniversalApk = false")

    meta_span = block_span(new, 'create("meta")')
    if meta_span is None:
        raise SystemExit('Could not find the create("meta") product flavor')

    meta_begin, meta_end = meta_span
    meta_block = new[meta_begin:meta_end]
    escaped_app_name = kotlin_string(app_name)
    meta_block, launch_name_count = re.subn(
        r'resValue\("string",\s*"launch_name",\s*"[^"]*"\)',
        f'resValue("string", "launch_name", "{escaped_app_name}")',
        meta_block,
        count=1,
    )
    meta_block, application_name_count = re.subn(
        r'resValue\("string",\s*"application_name",\s*"[^"]*"\)',
        f'resValue("string", "application_name", "{escaped_app_name}")',
        meta_block,
        count=1,
    )
    if launch_name_count != 1 or application_name_count != 1:
        raise SystemExit("Could not set the Meta flavor application labels")
    new = new[:meta_begin] + meta_block + new[meta_end:]

    if 'abiFilters += listOf("arm64-v8a")' not in new:
        raise SystemExit("Failed to restrict the Android NDK ABI list to arm64-v8a")
    if 'include("arm64-v8a")' not in new:
        raise SystemExit("Failed to restrict APK splits to arm64-v8a")
    if "isUniversalApk = false" not in new:
        raise SystemExit("Failed to disable the universal APK")
    if any(abi in new for abi in OTHER_ABIS):
        raise SystemExit("A non-arm64 ABI is still present in build.gradle.kts")

    write_if_changed(path, old, new)


def write_application_id(root: Path, application_id: str) -> None:
    path = root / "local.properties"
    old = path.read_text(encoding="utf-8") if path.is_file() else ""
    kept_lines = [
        line
        for line in old.splitlines()
        if not line.startswith(("custom.application.id=", "remove.suffix="))
    ]
    kept_lines.extend(
        (
            f"custom.application.id={application_id}",
            "remove.suffix=true",
        )
    )
    new = "\n".join(kept_lines) + "\n"
    write_if_changed(path, old, new)


def patch_core_build(root: Path) -> None:
    path = root / "core/build.gradle.kts"
    old = read(path)
    new, count = re.subn(
        r"(?m)^val abis = .+$",
        'val abis = listOf("arm64-v8a" to "Arm64V8a")',
        old,
        count=1,
    )
    if count != 1:
        raise SystemExit("Could not restrict the CMFA Go/CMake ABI task list")
    if any(abi in new for abi in OTHER_ABIS):
        raise SystemExit("A non-arm64 ABI is still present in core/build.gradle.kts")
    write_if_changed(path, old, new)


def patch_app_build(root: Path) -> None:
    path = root / "app/build.gradle.kts"
    old = read(path)
    new = old
    clean_task_marker = 'tasks.getByName("clean", type = Delete::class)'
    release_cleanup = 'delete(file("release"))'
    geo_cleanup = "delete(file(geoFilesDownloadDir))"
    clean_task_count = old.count(clean_task_marker)
    release_cleanup_count = old.count(release_cleanup)
    geo_cleanup_count = old.count(geo_cleanup)

    if geo_cleanup_count not in (0, 1):
        raise SystemExit(
            "Expected at most one Geo cleanup action in app/build.gradle.kts"
        )

    for import_name in (
        "import java.net.URL",
        "import java.nio.file.Files",
        "import java.nio.file.StandardCopyOption",
    ):
        new = remove_line_containing(new, import_name)

    new = remove_line_containing(new, "quickie")
    new = remove_block(new, 'task("downloadGeoFiles")')
    new = remove_block(new, "afterEvaluate {", "downloadGeoFilesTask")
    new = remove_block(
        new,
        'tasks.getByName("clean", type = Delete::class) {',
        "geoFilesDownloadDir",
    )
    new = remove_line_containing(new, "val geoFilesDownloadDir")

    if new.count(clean_task_marker) != clean_task_count - geo_cleanup_count:
        raise SystemExit(
            "Removing the Geo cleanup changed an unexpected clean task"
        )
    if new.count(release_cleanup) != release_cleanup_count:
        raise SystemExit(
            'The unrelated clean action delete(file("release")) was changed'
        )

    forbidden = ("quickie", "downloadGeoFiles", "geoFilesDownloadDir", *GEO_FILES)
    leftovers = [item for item in forbidden if item.lower() in new.lower()]
    if leftovers:
        raise SystemExit(f"app/build.gradle.kts still contains: {', '.join(leftovers)}")

    write_if_changed(path, old, new.rstrip() + "\n")


def patch_external_control_actions(root: Path) -> None:
    path = root / "app/src/main/AndroidManifest.xml"
    old = read(path)
    new = old

    for action in ("START_CLASH", "STOP_CLASH", "TOGGLE_CLASH"):
        official = (
            'android:name="com.github.metacubex.clash.meta.action.'
            f'{action}"'
        )
        package_scoped = (
            f'android:name="${{applicationId}}.action.{action}"'
        )
        official_count = new.count(official)
        package_scoped_count = new.count(package_scoped)

        if official_count == 1 and package_scoped_count == 0:
            new = new.replace(official, package_scoped, 1)
        elif official_count == 0 and package_scoped_count == 1:
            pass
        else:
            raise SystemExit(
                f"Expected one unambiguous {action} external-control action; "
                f"found official={official_count}, "
                f"package-scoped={package_scoped_count}"
            )

    if "com.github.metacubex.clash.meta.action." in new:
        raise SystemExit(
            "AndroidManifest.xml still contains an official package-scoped "
            "external-control action"
        )

    write_if_changed(path, old, new)


def patch_main_application(root: Path) -> None:
    path = (
        root
        / "app/src/main/java/com/github/kr328/clash/MainApplication.kt"
    )
    old = read(path)
    new = old

    for needle in (
        "import com.github.kr328.clash.util.clashDir",
        "import java.io.File",
        "import java.io.FileOutputStream",
        "        extractGeoFiles()",
    ):
        new = remove_line_containing(new, needle)

    new = remove_block(new, "    private fun extractGeoFiles()")

    forbidden = ("extractGeoFiles", *GEO_FILES)
    leftovers = [item for item in forbidden if item in new]
    if leftovers:
        raise SystemExit(f"MainApplication.kt still contains: {', '.join(leftovers)}")

    write_if_changed(path, old, new)


def patch_profile_provider(root: Path) -> None:
    path = (
        root
        / "design/src/main/java/com/github/kr328/clash/design/model/ProfileProvider.kt"
    )
    old = read(path)
    new = remove_block(old, "    class QR(")
    if "class QR(" in new:
        raise SystemExit("Failed to remove ProfileProvider.QR")
    write_if_changed(path, old, new)


def patch_new_profile_design(root: Path) -> None:
    path = (
        root
        / "design/src/main/java/com/github/kr328/clash/design/NewProfileDesign.kt"
    )
    old = read(path)
    new = remove_line_containing(old, "data class LaunchScanner")
    new = replace_function(
        new,
        "    private fun requestCreate(provider: ProfileProvider)",
        "    private fun requestCreate(provider: ProfileProvider) {\n"
        "        requests.trySend(Request.Create(provider))\n"
        "    }\n\n",
    )

    if "ProfileProvider.QR" in new or "LaunchScanner" in new:
        raise SystemExit("Failed to remove QR requests from NewProfileDesign.kt")
    write_if_changed(path, old, new)


def remove_import_if_unused(text: str, import_line: str, symbol: str) -> str:
    body = "".join(
        line
        for line in text.splitlines(keepends=True)
        if not line.lstrip().startswith("import ")
    )
    if re.search(rf"\b{re.escape(symbol)}\b", body) is None:
        return remove_line_containing(text, import_line)
    return text


def patch_new_profile_activity(root: Path) -> None:
    path = (
        root
        / "app/src/main/java/com/github/kr328/clash/NewProfileActivity.kt"
    )
    old = read(path)
    new = old

    new = remove_line_containing(new, "io.github.g00fy2.quickie")
    new = remove_line_containing(new, "private val scanLauncher")
    new = re.sub(
        r"(?ms)^[ \t]+is ProfileProvider\.QR -> "
        r"\{[ \t\r\n]*null[ \t\r\n]*\}[ \t]*\r?\n",
        "",
        new,
    )
    new = re.sub(
        r"(?ms)^[ \t]+is NewProfileDesign\.Request\.LaunchScanner -> "
        r"\{[ \t\r\n]*scanLauncher\.launch\(null\)[ \t\r\n]*\}[ \t]*\r?\n",
        "",
        new,
    )
    new = remove_line_containing(new, "ProfileProvider.QR(self)")
    new = remove_block(new, "    private fun scanResultHandler(")
    new = remove_block(new, "    private suspend fun createProfileByQrCode(")

    new = remove_import_if_unused(
        new, "import androidx.lifecycle.lifecycleScope", "lifecycleScope"
    )
    new = remove_import_if_unused(
        new,
        "import com.github.kr328.clash.design.util.showExceptionToast",
        "showExceptionToast",
    )
    new = remove_import_if_unused(
        new, "import kotlinx.coroutines.launch", "launch"
    )

    forbidden = (
        "quickie",
        "ScanQRCode",
        "QRResult",
        "ProfileProvider.QR",
        "LaunchScanner",
        "scanLauncher",
        "scanResultHandler",
        "createProfileByQrCode",
    )
    leftovers = [item for item in forbidden if item in new]
    if leftovers:
        raise SystemExit(f"NewProfileActivity.kt still contains: {', '.join(leftovers)}")

    write_if_changed(path, old, new)


def remove_geo_assets(root: Path) -> None:
    assets = root / "app/src/main/assets"
    for filename in GEO_FILES:
        path = assets / filename
        if path.exists():
            path.unlink()
            print(f"deleted: {path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-revision", type=int, required=True)
    parser.add_argument("--core-version", required=True)
    parser.add_argument("--app-name", required=True)
    parser.add_argument("--application-id", required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    app_name = args.app_name.strip()
    application_id = args.application_id.strip()
    core_version = args.core_version.strip()
    source_version, base_version_code = parse_version(args.version)

    if not app_name or "\n" in app_name or "\r" in app_name:
        raise SystemExit("APP_NAME must be a non-empty single-line value")
    if not APPLICATION_ID_PATTERN.fullmatch(application_id):
        raise SystemExit(
            "APPLICATION_ID must contain at least two lowercase dot-separated "
            f"segments, received: {application_id}"
        )

    version_name, version_code = make_app_version(
        source_version,
        base_version_code,
        args.build_revision,
        app_name,
        core_version,
    )
    patch_root_build(root, version_name, version_code, app_name)
    write_application_id(root, application_id)
    patch_core_build(root)
    patch_app_build(root)
    patch_external_control_actions(root)
    patch_main_application(root)
    patch_profile_provider(root)
    patch_new_profile_design(root)
    patch_new_profile_activity(root)
    remove_geo_assets(root)
    export_github_metadata(version_name, version_code)

    print(
        f"CMFA source prepared: app={app_name}, applicationId={application_id}, "
        f"version={version_name}, core={core_version}, "
        f"versionCode={version_code}, ABI=arm64-v8a, QR=off, bundled Geo=off, "
        "external control=package-scoped"
    )


if __name__ == "__main__":
    main()
