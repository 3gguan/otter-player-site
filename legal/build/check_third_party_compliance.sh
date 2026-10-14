#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${PROJECT_DIR}/Compliance/THIRD_PARTY_MANIFEST.json"
PACKAGE_RESOLVED="${PROJECT_DIR}/xPlayer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
FFMPEG_BUILD_ROOT="${FFMPEG_BUILD_ROOT:-${PROJECT_DIR}/Build/FFmpeg}"

fail() {
  echo "Compliance check failed: $*" >&2
  exit 1
}

for command_name in ruby rg shasum; do
  command -v "${command_name}" >/dev/null || fail "missing command ${command_name}"
done

required_files=(
  "${MANIFEST}"
  "${PACKAGE_RESOLVED}"
  "${PROJECT_DIR}/Compliance/LICENSE_SHA256SUMS"
  "${PROJECT_DIR}/Compliance/EULA_LGPL_EXCEPTION.md"
  "${PROJECT_DIR}/Compliance/RELINKING.md"
  "${PROJECT_DIR}/Compliance/RELEASE_CHECKLIST.md"
  "${PROJECT_DIR}/Compliance/Licenses/LGPL-2.1.txt"
  "${PROJECT_DIR}/Compliance/Licenses/taglib-COPYING.MPL.txt"
  "${PROJECT_DIR}/Compliance/Licenses/taglib-COPYING.LGPL.txt"
  "${PROJECT_DIR}/Compliance/Licenses/utfcpp-LICENSE.txt"
  "${PROJECT_DIR}/Compliance/Licenses/pupnp-BSD-3-Clause.txt"
  "${PROJECT_DIR}/Vendor/PUPnP/COPYING.pupnp"
  "${PROJECT_DIR}/Vendor/PUPnP/SOURCE_STATE.txt"
  "${PROJECT_DIR}/Compliance/Licenses/swift-nio-NOTICE.txt"
  "${PROJECT_DIR}/Vendor/TagLib/SOURCE_STATE.txt"
  "${PROJECT_DIR}/Vendor/TagLib/COPYING.MPL"
  "${PROJECT_DIR}/Vendor/TagLib/COPYING.LGPL"
  "${PROJECT_DIR}/Vendor/TagLib/LICENSE.utfcpp"
  "${PROJECT_DIR}/Vendor/FFmpeg/SOURCE_STATE.txt"
  "${PROJECT_DIR}/Vendor/NetworkLibraries/SOURCE_STATE.txt"
  "${PROJECT_DIR}/Vendor/NetworkLibraries/COPYING.libsmb2"
  "${PROJECT_DIR}/Vendor/NetworkLibraries/COPYING.libnfs"
  "${PROJECT_DIR}/Vendor/NetworkLibraries/COPYING.LGPLv2.1"
  "${PROJECT_DIR}/Vendor/NetworkLibraries/LICENCE-BSD.libnfs"
)

for required_file in "${required_files[@]}"; do
  [[ -f "${required_file}" ]] || fail "missing ${required_file}"
done

(
  cd "${PROJECT_DIR}"
  shasum -a 256 -c Compliance/LICENSE_SHA256SUMS >/dev/null
) || fail "a tracked license or notice differs from its recorded source copy"

"${PROJECT_DIR}/Scripts/generate_third_party_notices.sh" --check >/dev/null

ruby -rjson -e '
  manifest = JSON.parse(File.read(ARGV.fetch(0)))
  resolved = JSON.parse(File.read(ARGV.fetch(1)))
  components = manifest.fetch("components").to_h { |item| [item.fetch("name"), item] }
  pins = resolved.fetch("pins").to_h { |pin| [pin.fetch("identity"), pin.fetch("state")] }
  expected = {
    "SwiftNIO" => ["swift-nio", "2.99.0"],
    "Swift Atomics" => ["swift-atomics", "1.3.0"],
    "Swift Collections" => ["swift-collections", "1.4.1"],
    "Swift System" => ["swift-system", "1.6.4"]
  }
  expected.each do |component_name, (identity, version)|
    component = components.fetch(component_name)
    pin = pins.fetch(identity)
    abort("#{identity} version mismatch") unless pin.fetch("version") == version && component.fetch("version") == version
    abort("#{identity} revision mismatch") unless pin.fetch("revision") == component.fetch("revision")
  end
' "${MANIFEST}" "${PACKAGE_RESOLVED}" || fail "Swift Package pins do not match the manifest"

for slice_name in iphoneos-arm64 iphonesimulator-arm64 iphonesimulator-x86_64; do
  config_file="${FFMPEG_BUILD_ROOT}/${slice_name}/build/config.h"
  [[ -f "${config_file}" ]] || fail "missing FFmpeg config for ${slice_name}"
  for disabled_flag in \
    CONFIG_GPL \
    CONFIG_NONFREE \
    CONFIG_VERSION3 \
    CONFIG_LIBSMBCLIENT \
    CONFIG_OPENSSL \
    CONFIG_LIBX264 \
    CONFIG_LIBX265; do
    grep -q "^#define ${disabled_flag} 0$" "${config_file}" || fail "${disabled_flag} is not 0 in ${config_file}"
  done
  grep -q '^#define CONFIG_SECURETRANSPORT 1$' "${config_file}" || fail "SecureTransport is not enabled in ${config_file}"
done

cmp -s "${PROJECT_DIR}/Compliance/Licenses/libsmb2-COPYING.txt" \
  "${PROJECT_DIR}/Vendor/NetworkLibraries/COPYING.libsmb2" || fail "Vendor libsmb2 COPYING is stale"
cmp -s "${PROJECT_DIR}/Compliance/Licenses/libnfs-COPYING.txt" \
  "${PROJECT_DIR}/Vendor/NetworkLibraries/COPYING.libnfs" || fail "Vendor libnfs COPYING is stale"
cmp -s "${PROJECT_DIR}/Compliance/Licenses/LGPL-2.1.txt" \
  "${PROJECT_DIR}/Vendor/NetworkLibraries/COPYING.LGPLv2.1" || fail "Vendor LGPL text is stale"
cmp -s "${PROJECT_DIR}/Compliance/Licenses/libnfs-BSD-2-Clause.txt" \
  "${PROJECT_DIR}/Vendor/NetworkLibraries/LICENCE-BSD.libnfs" || fail "Vendor libnfs BSD text is stale"
cmp -s "${PROJECT_DIR}/Compliance/Licenses/FFmpeg-LICENSE.md" \
  "${PROJECT_DIR}/Vendor/FFmpeg/LICENSE.md" || fail "Vendor FFmpeg LICENSE is stale"
cmp -s "${PROJECT_DIR}/Compliance/Licenses/LGPL-2.1.txt" \
  "${PROJECT_DIR}/Vendor/FFmpeg/COPYING.LGPLv2.1" || fail "Vendor FFmpeg LGPL text is stale"
cmp -s "${PROJECT_DIR}/Compliance/Licenses/taglib-COPYING.MPL.txt" \
  "${PROJECT_DIR}/Vendor/TagLib/COPYING.MPL" || fail "Vendor TagLib MPL text is stale"
cmp -s "${PROJECT_DIR}/Compliance/Licenses/taglib-COPYING.LGPL.txt" \
  "${PROJECT_DIR}/Vendor/TagLib/COPYING.LGPL" || fail "Vendor TagLib LGPL text is stale"
cmp -s "${PROJECT_DIR}/Compliance/Licenses/utfcpp-LICENSE.txt" \
  "${PROJECT_DIR}/Vendor/TagLib/LICENSE.utfcpp" || fail "Vendor utfcpp license text is stale"
cmp -s "${PROJECT_DIR}/Compliance/Licenses/pupnp-BSD-3-Clause.txt" \
  "${PROJECT_DIR}/Vendor/PUPnP/COPYING.pupnp" || fail "Vendor pupnp license text is stale"

rg -F 'revision=9abe92e3af7fa7becc8f7f742b1457b4c28220a6' \
  "${PROJECT_DIR}/Vendor/FFmpeg/SOURCE_STATE.txt" >/dev/null || fail "Vendor FFmpeg source state is stale"
rg -F 'libsmb2.revision=d67e213a5c4e7e4969fd81f0b95e4ca5831fbba1' \
  "${PROJECT_DIR}/Vendor/NetworkLibraries/SOURCE_STATE.txt" >/dev/null || fail "Vendor libsmb2 source state is stale"
rg -F 'libnfs.revision=18c5c73ee88bb7dc8da0d55dc95164bb77e49dc6' \
  "${PROJECT_DIR}/Vendor/NetworkLibraries/SOURCE_STATE.txt" >/dev/null || fail "Vendor libnfs source state is stale"
rg -F 'taglib.revision=deadc2990767dfbda0701e0ab35fdeea653db08f' \
  "${PROJECT_DIR}/Vendor/TagLib/SOURCE_STATE.txt" >/dev/null || fail "Vendor TagLib source state is stale"
rg -F 'taglib.license=MPL-1.1 (elected from MPL-1.1 / LGPL-2.1)' \
  "${PROJECT_DIR}/Vendor/TagLib/SOURCE_STATE.txt" >/dev/null || fail "Vendor TagLib elected license is stale"
rg -F 'utfcpp.revision=2d8e20b22dcb3e9b3c4f52103182ebda949c6089' \
  "${PROJECT_DIR}/Vendor/TagLib/SOURCE_STATE.txt" >/dev/null || fail "Vendor utfcpp source state is stale"
rg -F 'revision=4145da68112f61660c8e55ed61fae1bb07d0e3d8' \
  "${PROJECT_DIR}/Vendor/PUPnP/SOURCE_STATE.txt" >/dev/null || fail "Vendor pupnp source state is stale"
rg -F '"revision": "deadc2990767dfbda0701e0ab35fdeea653db08f"' \
  "${MANIFEST}" >/dev/null || fail "TagLib revision is missing from the manifest"
rg -F '"revision": "2d8e20b22dcb3e9b3c4f52103182ebda949c6089"' \
  "${MANIFEST}" >/dev/null || fail "utfcpp revision is missing from the manifest"
rg -F '"revision": "4145da68112f61660c8e55ed61fae1bb07d0e3d8"' \
  "${MANIFEST}" >/dev/null || fail "pupnp revision is missing from the manifest"

if rg -n -- '--enable-(gpl|nonfree|version3|libsmbclient|openssl|libx264|libx265)(=|[[:space:]]|$)' \
  "${PROJECT_DIR}/Scripts/build_ffmpeg_ios.sh" >/dev/null; then
  fail "a forbidden FFmpeg enable flag is present in the build script"
fi

for required_network_flag in \
  '-DBUILD_EXAMPLES=OFF' \
  '-DBUILD_TESTING=OFF' \
  '-DENABLE_EXAMPLES=OFF' \
  '-DENABLE_TESTS=OFF' \
  '-DENABLE_UTILS=OFF'; do
  rg -F -- "${required_network_flag}" "${PROJECT_DIR}/Scripts/build_network_libraries_ios.sh" >/dev/null \
    || fail "network build script is missing ${required_network_flag}"
done

for required_taglib_flag in \
  '-DBUILD_SHARED_LIBS=OFF' \
  '-DBUILD_TESTING=OFF' \
  '-DBUILD_EXAMPLES=OFF' \
  '-DBUILD_BINDINGS=OFF' \
  '-DWITH_MOD=OFF' \
  '-DWITH_SHORTEN=OFF'; do
  rg -F -- "${required_taglib_flag}" "${PROJECT_DIR}/Scripts/build_taglib_ios.sh" >/dev/null \
    || fail "TagLib build script is missing ${required_taglib_flag}"
done

check_source_revision() {
  local name="$1"
  local source_dir="$2"
  local expected_revision="$3"
  git -C "${source_dir}" rev-parse --git-dir >/dev/null 2>&1 \
    || fail "${name} source is not a Git checkout: ${source_dir}"
  local actual_revision
  actual_revision="$(git -C "${source_dir}" rev-parse HEAD)"
  [[ "${actual_revision}" == "${expected_revision}" ]] || fail "${name} revision is ${actual_revision}, expected ${expected_revision}"
  [[ -z "$(git -C "${source_dir}" status --porcelain --untracked-files=all)" ]] || fail "${name} source checkout is dirty"
}

if [[ -n "${FFMPEG_SOURCE_DIR:-}" || -n "${LIBSMB2_SOURCE_DIR:-}" || -n "${LIBNFS_SOURCE_DIR:-}" ]]; then
  [[ -n "${FFMPEG_SOURCE_DIR:-}" && -n "${LIBSMB2_SOURCE_DIR:-}" && -n "${LIBNFS_SOURCE_DIR:-}" ]] \
    || fail "set all three source directory variables when checking source revisions"
  check_source_revision FFmpeg "${FFMPEG_SOURCE_DIR}" 9abe92e3af7fa7becc8f7f742b1457b4c28220a6
  check_source_revision libsmb2 "${LIBSMB2_SOURCE_DIR}" d67e213a5c4e7e4969fd81f0b95e4ca5831fbba1
  check_source_revision libnfs "${LIBNFS_SOURCE_DIR}" 18c5c73ee88bb7dc8da0d55dc95164bb77e49dc6
fi

if [[ -n "${PUPNP_SOURCE_DIR:-}" ]]; then
  check_source_revision pupnp "${PUPNP_SOURCE_DIR}" 4145da68112f61660c8e55ed61fae1bb07d0e3d8
fi

if [[ -n "${TAGLIB_SOURCE_DIR:-}" ]]; then
  check_source_revision TagLib "${TAGLIB_SOURCE_DIR}" deadc2990767dfbda0701e0ab35fdeea653db08f
  check_source_revision utfcpp "${TAGLIB_SOURCE_DIR}/3rdparty/utfcpp" 2d8e20b22dcb3e9b3c4f52103182ebda949c6089
fi

if [[ -n "${APP_BUNDLE:-}" ]]; then
  [[ -d "${APP_BUNDLE}" ]] || fail "APP_BUNDLE is not a directory: ${APP_BUNDLE}"
  bundled_notice="$(find "${APP_BUNDLE}" -type f -name 'ThirdPartyNotices.txt' -print -quit)"
  [[ -z "${bundled_notice}" ]] || fail "App bundle must not contain ThirdPartyNotices.txt: ${bundled_notice}"

  app_binary="${APP_BUNDLE}/Otter Player"
  [[ -f "${app_binary}" ]] || fail "App executable not found at ${app_binary}"
  if strings "${app_binary}" | rg -i -- '--enable-(gpl|nonfree|version3|libsmbclient|openssl|libx264|libx265)|lib(x264|x265|smbclient|ssl|crypto)' >/dev/null; then
    fail "App executable contains a GPL/nonfree/high-risk dependency marker"
  fi
  if xcrun otool -L "${app_binary}" | rg -i 'lib(x264|x265|smbclient|ssl|crypto)' >/dev/null; then
    fail "App executable dynamically references a GPL/nonfree/high-risk dependency"
  fi
fi

if [[ -n "${RELINK_PACKAGE:-}" ]]; then
  [[ -d "${RELINK_PACKAGE}" ]] || fail "RELINK_PACKAGE is not a directory"
  [[ -f "${RELINK_PACKAGE}/relink/archive-build.log" ]] || fail "relink package has no archive build log"
  [[ -f "${RELINK_PACKAGE}/sources/FFmpeg-n7.1.4.tar.gz" ]] || fail "relink package has no FFmpeg source archive"
  [[ -f "${RELINK_PACKAGE}/sources/libsmb2-6.2.tar.gz" ]] || fail "relink package has no libsmb2 source archive"
  [[ -f "${RELINK_PACKAGE}/sources/libnfs-6.0.2.tar.gz" ]] || fail "relink package has no libnfs source archive"
  app_object_count="$(find "${RELINK_PACKAGE}/relink/intermediates" \
    -type f -path '*/xPlayer.build/Release-iphoneos/xPlayer.build/Objects-normal/arm64/*.o' \
    | wc -l | tr -d ' ')"
  [[ "${app_object_count}" -gt 0 ]] || fail "relink package contains no xPlayer arm64 object files"
  link_file_count="$(find "${RELINK_PACKAGE}/relink/intermediates" \
    -type f -path '*/xPlayer.build/Release-iphoneos/xPlayer.build/Objects-normal/arm64/xPlayer.LinkFileList' \
    | wc -l | tr -d ' ')"
  [[ "${link_file_count}" -gt 0 ]] || fail "relink package contains no xPlayer arm64 LinkFileList"
  release_product_dir="$(find "${RELINK_PACKAGE}/relink/intermediates" \
    -type d -path '*/BuildProductsPath/Release-iphoneos' -print -quit)"
  [[ -n "${release_product_dir}" ]] || fail "relink package contains no archive Release products"
  while IFS= read -r product_link; do
    [[ -e "${product_link}" ]] || fail "relink package contains a broken product link: ${product_link}"
  done < <(find "${release_product_dir}" -type l -print)
fi

echo "Third-party compliance checks passed."
