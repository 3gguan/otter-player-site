#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${PROJECT_DIR}/Build/NetworkLibraries"
OUTPUT_DIR="${PROJECT_DIR}/Vendor/NetworkLibraries"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-16.0}"

LIBSMB2_SOURCE_DIR="${LIBSMB2_SOURCE_DIR:-${PROJECT_DIR}/ThirdPartySources/libsmb2}"
LIBNFS_SOURCE_DIR="${LIBNFS_SOURCE_DIR:-${PROJECT_DIR}/ThirdPartySources/libnfs}"
EXPECTED_LIBSMB2_REVISION="d67e213a5c4e7e4969fd81f0b95e4ca5831fbba1"
EXPECTED_LIBNFS_REVISION="18c5c73ee88bb7dc8da0d55dc95164bb77e49dc6"

require_dir() {
  local path="$1"
  if [[ ! -d "${path}" ]]; then
    echo "Missing source directory: ${path}" >&2
    exit 1
  fi
}

require_clean_source_revision() {
  local name="$1"
  local source_dir="$2"
  local expected_revision="$3"
  local actual_revision
  actual_revision="$(git -C "${source_dir}" rev-parse HEAD)"
  if [[ "${actual_revision}" != "${expected_revision}" ]]; then
    echo "${name} revision ${actual_revision} does not match ${expected_revision}" >&2
    exit 1
  fi
  if [[ -n "$(git -C "${source_dir}" status --porcelain --untracked-files=all)" ]]; then
    echo "${name} source checkout is dirty; update the manifest and patch workflow before building" >&2
    exit 1
  fi
}

build_cmake_slice() {
  local name="$1"
  local source_dir="$2"
  local sdk_name="$3"
  local archs="$4"
  local build_dir="${BUILD_ROOT}/${name}/${sdk_name}/build"
  local install_dir="${BUILD_ROOT}/${name}/${sdk_name}/install"
  shift 4

  local sdk_path
  sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"

  rm -rf "${build_dir}" "${install_dir}"
  mkdir -p "${build_dir}" "${install_dir}"

  cmake -S "${source_dir}" -B "${build_dir}" \
    -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="${sdk_path}" \
    -DCMAKE_OSX_ARCHITECTURES="${archs}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_IOS_VERSION}" \
    -DCMAKE_INSTALL_PREFIX="${install_dir}" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    "$@"

  cmake --build "${build_dir}" --config Release --parallel "$(sysctl -n hw.ncpu)"
  cmake --install "${build_dir}" --config Release
}

find_static_library() {
  local install_dir="$1"
  local library_name="$2"
  local library_path
  library_path="$(find "${install_dir}" -type f -name "lib${library_name}.a" -print -quit)"
  if [[ -z "${library_path}" ]]; then
    echo "Could not find lib${library_name}.a under ${install_dir}" >&2
    exit 1
  fi
  echo "${library_path}"
}

create_xcframework() {
  local product_name="$1"
  local library_name="$2"
  local device_install="${BUILD_ROOT}/${product_name}/iphoneos/install"
  local simulator_install="${BUILD_ROOT}/${product_name}/iphonesimulator/install"
  local output_path="${OUTPUT_DIR}/lib${library_name}.xcframework"
  local device_library
  local simulator_library

  device_library="$(find_static_library "${device_install}" "${library_name}")"
  simulator_library="$(find_static_library "${simulator_install}" "${library_name}")"

  rm -rf "${output_path}"
  xcodebuild -create-xcframework \
    -library "${device_library}" \
    -headers "${device_install}/include" \
    -library "${simulator_library}" \
    -headers "${simulator_install}/include" \
    -output "${output_path}"
}

require_dir "${LIBSMB2_SOURCE_DIR}"
require_dir "${LIBNFS_SOURCE_DIR}"
require_clean_source_revision libsmb2 "${LIBSMB2_SOURCE_DIR}" "${EXPECTED_LIBSMB2_REVISION}"
require_clean_source_revision libnfs "${LIBNFS_SOURCE_DIR}" "${EXPECTED_LIBNFS_REVISION}"

mkdir -p "${OUTPUT_DIR}"

build_cmake_slice libsmb2 "${LIBSMB2_SOURCE_DIR}" iphoneos arm64 \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_TESTING=OFF \
  -DENABLE_EXAMPLES=OFF \
  -DENABLE_TESTS=OFF

build_cmake_slice libsmb2 "${LIBSMB2_SOURCE_DIR}" iphonesimulator "arm64;x86_64" \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_TESTING=OFF \
  -DENABLE_EXAMPLES=OFF \
  -DENABLE_TESTS=OFF

build_cmake_slice libnfs "${LIBNFS_SOURCE_DIR}" iphoneos arm64 \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_TESTING=OFF \
  -DENABLE_TESTS=OFF \
  -DENABLE_UTILS=OFF

build_cmake_slice libnfs "${LIBNFS_SOURCE_DIR}" iphonesimulator "arm64;x86_64" \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_TESTING=OFF \
  -DENABLE_TESTS=OFF \
  -DENABLE_UTILS=OFF

create_xcframework libsmb2 smb2
create_xcframework libnfs nfs

cp "${LIBSMB2_SOURCE_DIR}/COPYING" "${OUTPUT_DIR}/COPYING.libsmb2"
cp "${LIBSMB2_SOURCE_DIR}/LICENCE-LGPL-2.1.txt" "${OUTPUT_DIR}/COPYING.LGPLv2.1"
cp "${LIBNFS_SOURCE_DIR}/COPYING" "${OUTPUT_DIR}/COPYING.libnfs"
cp "${LIBNFS_SOURCE_DIR}/LICENCE-BSD.txt" "${OUTPUT_DIR}/LICENCE-BSD.libnfs"
{
  echo "libsmb2.source=https://github.com/sahlberg/libsmb2.git"
  echo "libsmb2.version=libsmb2-6.2"
  echo "libsmb2.revision=${EXPECTED_LIBSMB2_REVISION}"
  echo "libsmb2.modified=false"
  echo "libnfs.source=https://github.com/sahlberg/libnfs.git"
  echo "libnfs.version=libnfs-6.0.2"
  echo "libnfs.revision=${EXPECTED_LIBNFS_REVISION}"
  echo "libnfs.modified=false"
} > "${OUTPUT_DIR}/SOURCE_STATE.txt"

echo "Network libraries are available under ${OUTPUT_DIR}"
