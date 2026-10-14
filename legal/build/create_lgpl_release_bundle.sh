#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  Scripts/create_lgpl_release_bundle.sh RELEASE_ID XCARCHIVE_PATH DERIVED_DATA_PATH ARCHIVE_BUILD_LOG OUTPUT_DIR

Required source checkouts may be supplied with:
  FFMPEG_SOURCE_DIR, LIBSMB2_SOURCE_DIR, LIBNFS_SOURCE_DIR

Without those variables, the script uses:
  ThirdPartySources/FFmpeg
  ThirdPartySources/libsmb2
  ThirdPartySources/libnfs
USAGE
}

if [[ $# -ne 5 ]]; then
  usage >&2
  exit 64
fi

RELEASE_ID="$1"
XCARCHIVE_PATH="$2"
DERIVED_DATA_PATH="$3"
ARCHIVE_BUILD_LOG="$4"
OUTPUT_DIR="$5"
FFMPEG_SOURCE_DIR="${FFMPEG_SOURCE_DIR:-${PROJECT_DIR}/ThirdPartySources/FFmpeg}"
LIBSMB2_SOURCE_DIR="${LIBSMB2_SOURCE_DIR:-${PROJECT_DIR}/ThirdPartySources/libsmb2}"
LIBNFS_SOURCE_DIR="${LIBNFS_SOURCE_DIR:-${PROJECT_DIR}/ThirdPartySources/libnfs}"
FFMPEG_BUILD_ROOT="${FFMPEG_BUILD_ROOT:-${PROJECT_DIR}/Build/FFmpeg}"
NETWORK_BUILD_ROOT="${NETWORK_BUILD_ROOT:-${PROJECT_DIR}/Build/NetworkLibraries}"

[[ "${RELEASE_ID}" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid RELEASE_ID" >&2; exit 1; }
[[ -d "${XCARCHIVE_PATH}" ]] || { echo "Archive not found: ${XCARCHIVE_PATH}" >&2; exit 1; }
[[ -d "${DERIVED_DATA_PATH}/Build" ]] || { echo "DerivedData Build directory not found: ${DERIVED_DATA_PATH}" >&2; exit 1; }
[[ -f "${ARCHIVE_BUILD_LOG}" ]] || { echo "Archive build log not found: ${ARCHIVE_BUILD_LOG}" >&2; exit 1; }

app_bundle="${XCARCHIVE_PATH}/Products/Applications/Otter Player.app"
[[ -d "${app_bundle}" ]] || { echo "Otter Player.app not found in archive" >&2; exit 1; }

mkdir -p "${OUTPUT_DIR}"
output_zip="${OUTPUT_DIR}/OtterPlayer-${RELEASE_ID}-LGPL-Compliance.zip"
[[ ! -e "${output_zip}" ]] || { echo "Refusing to overwrite ${output_zip}" >&2; exit 1; }

export FFMPEG_SOURCE_DIR LIBSMB2_SOURCE_DIR LIBNFS_SOURCE_DIR FFMPEG_BUILD_ROOT
APP_BUNDLE="${app_bundle}" "${PROJECT_DIR}/Scripts/check_third_party_compliance.sh"

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/otterplayer-lgpl-release.XXXXXX")"
trap 'rm -rf "${temp_dir}"' EXIT
package_root="${temp_dir}/OtterPlayer-${RELEASE_ID}-LGPL-Compliance"
mkdir -p \
  "${package_root}/licenses" \
  "${package_root}/sources/patches" \
  "${package_root}/build-materials/ffmpeg-config" \
  "${package_root}/build-materials/network-config" \
  "${package_root}/build-materials/original-lgpl-libraries" \
  "${package_root}/relink/intermediates" \
  "${package_root}/original-binary"

archive_source() {
  local source_dir="$1"
  local prefix="$2"
  local output_name="$3"
  local patch_name="$4"

  if [[ -n "$(git -C "${source_dir}" ls-files --others --exclude-standard)" ]]; then
    echo "Untracked files in ${source_dir}; add or remove them before packaging" >&2
    exit 1
  fi
  git -C "${source_dir}" archive --format=tar.gz --prefix="${prefix}/" HEAD > "${package_root}/sources/${output_name}"
  git -C "${source_dir}" diff --binary HEAD > "${package_root}/sources/patches/${patch_name}"
}

archive_source "${FFMPEG_SOURCE_DIR}" "FFmpeg-n7.1.4" "FFmpeg-n7.1.4.tar.gz" "FFmpeg-n7.1.4.patch"
archive_source "${LIBSMB2_SOURCE_DIR}" "libsmb2-6.2" "libsmb2-6.2.tar.gz" "libsmb2-6.2.patch"
archive_source "${LIBNFS_SOURCE_DIR}" "libnfs-6.0.2" "libnfs-6.0.2.tar.gz" "libnfs-6.0.2.patch"

ditto "${PROJECT_DIR}/Compliance/Licenses" "${package_root}/licenses"
cp "${PROJECT_DIR}/Compliance/THIRD_PARTY_MANIFEST.json" "${package_root}/"
cp "${PROJECT_DIR}/Compliance/RELINKING.md" "${package_root}/relink/README.md"
cp "${PROJECT_DIR}/Compliance/EULA_LGPL_EXCEPTION.md" "${package_root}/"
cp "${PROJECT_DIR}/Compliance/THIRD_PARTY_NOTICES.txt" "${package_root}/licenses/"
cp "${PROJECT_DIR}/Scripts/build_ffmpeg_ios.sh" "${package_root}/build-materials/"
cp "${PROJECT_DIR}/Scripts/build_network_libraries_ios.sh" "${package_root}/build-materials/"
cp "${PROJECT_DIR}/xPlayer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" "${package_root}/build-materials/"
cp "${PROJECT_DIR}/xPlayer.xcodeproj/project.pbxproj" "${package_root}/build-materials/"
cp "${PROJECT_DIR}/xPlayer.xcodeproj/xcshareddata/xcschemes/xPlayer.xcscheme" "${package_root}/build-materials/"
cp "${ARCHIVE_BUILD_LOG}" "${package_root}/relink/archive-build.log"
ditto "${app_bundle}" "${package_root}/original-binary/Otter Player.app"
ditto "${PROJECT_DIR}/Vendor/FFmpeg" "${package_root}/build-materials/original-lgpl-libraries/FFmpeg"
ditto "${PROJECT_DIR}/Vendor/NetworkLibraries" "${package_root}/build-materials/original-lgpl-libraries/NetworkLibraries"

config_count=0
for config_file in "${FFMPEG_BUILD_ROOT}"/*/build/config.h; do
  [[ -f "${config_file}" ]] || continue
  slice_name="$(basename "$(dirname "$(dirname "${config_file}")")")"
  mkdir -p "${package_root}/build-materials/ffmpeg-config/${slice_name}"
  cp "${config_file}" "${package_root}/build-materials/ffmpeg-config/${slice_name}/config.h"
  components_file="$(dirname "${config_file}")/config_components.h"
  [[ -f "${components_file}" ]] && cp "${components_file}" "${package_root}/build-materials/ffmpeg-config/${slice_name}/config_components.h"
  config_mak="$(dirname "${config_file}")/ffbuild/config.mak"
  [[ -f "${config_mak}" ]] && cp "${config_mak}" "${package_root}/build-materials/ffmpeg-config/${slice_name}/config.mak"
  config_count=$((config_count + 1))
done
[[ ${config_count} -gt 0 ]] || { echo "No FFmpeg build configurations found" >&2; exit 1; }

network_config_count=0
for library_name in libsmb2 libnfs; do
  for cache_file in "${NETWORK_BUILD_ROOT}/${library_name}"/*/build/CMakeCache.txt; do
    [[ -f "${cache_file}" ]] || continue
    relative_cache="${cache_file#${NETWORK_BUILD_ROOT}/}"
    destination="${package_root}/build-materials/network-config/${relative_cache}"
    mkdir -p "$(dirname "${destination}")"
    cp "${cache_file}" "${destination}"
    flags_dir="$(dirname "${cache_file}")/CMakeFiles"
    if [[ -d "${flags_dir}" ]]; then
      while IFS= read -r flags_file; do
        relative_flags="${flags_file#${NETWORK_BUILD_ROOT}/}"
        flags_destination="${package_root}/build-materials/network-config/${relative_flags}"
        mkdir -p "$(dirname "${flags_destination}")"
        cp "${flags_file}" "${flags_destination}"
      done < <(find "${flags_dir}" -type f -name flags.make -print)
    fi
    network_config_count=$((network_config_count + 1))
  done
done
[[ ${network_config_count} -eq 4 ]] || { echo "Expected four network library CMake configurations, found ${network_config_count}" >&2; exit 1; }

intermediates_root="${DERIVED_DATA_PATH}/Build/Intermediates.noindex"
while IFS= read -r release_dir; do
  relative_path="${release_dir#${intermediates_root}/}"
  destination="${package_root}/relink/intermediates/${relative_path}"
  mkdir -p "$(dirname "${destination}")"
  ditto "${release_dir}" "${destination}"
done < <(find "${intermediates_root}" -type d -name Release-iphoneos -print)

release_products="${DERIVED_DATA_PATH}/Build/Products/Release-iphoneos"
if [[ ! -d "${release_products}" ]]; then
  release_products="$(find "${intermediates_root}/ArchiveIntermediates" \
    -type d -path '*/BuildProductsPath/Release-iphoneos' -print -quit)"
fi
[[ -n "${release_products}" && -d "${release_products}" ]] \
  || { echo "Release products not found in DerivedData" >&2; exit 1; }

archive_intermediates="${release_products%/BuildProductsPath/Release-iphoneos}"
if [[ "${archive_intermediates}" != "${release_products}" ]]; then
  source_directory="${archive_intermediates}/IntermediateBuildFilesPath/UninstalledProducts/iphoneos"
  [[ -d "${source_directory}" ]] || { echo "Missing archive relink directory: ${source_directory}" >&2; exit 1; }
  relative_directory="${source_directory#${intermediates_root}/}"
  destination_directory="${package_root}/relink/intermediates/${relative_directory}"
  mkdir -p "$(dirname "${destination_directory}")"
  ditto "${source_directory}" "${destination_directory}"

  archive_relative="${archive_intermediates#${intermediates_root}/}"
  installation_app="${package_root}/relink/intermediates/${archive_relative}/InstallationBuildProductsLocation/Applications/Otter Player.app"
  mkdir -p "$(dirname "${installation_app}")"
  ditto "${app_bundle}" "${installation_app}"
fi

object_count="$(find "${package_root}/relink" -type f -name '*.o' | wc -l | tr -d ' ')"
[[ "${object_count}" -gt 0 ]] || { echo "No Release object files were found" >&2; exit 1; }

{
  echo "Release ID: ${RELEASE_ID}"
  echo "Archive: $(basename "${XCARCHIVE_PATH}")"
  echo "Application objects: ${object_count}"
  echo
  xcodebuild -version
  xcrun --sdk iphoneos clang --version | head -1
  xcrun swift --version
  sw_vers
} > "${package_root}/RELEASE_METADATA.txt"

RELINK_PACKAGE="${package_root}" APP_BUNDLE="${app_bundle}" \
  "${PROJECT_DIR}/Scripts/check_third_party_compliance.sh"

(
  cd "${package_root}"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS
)

ditto -c -k --sequesterRsrc --keepParent "${package_root}" "${output_zip}"
echo "Created ${output_zip}"
