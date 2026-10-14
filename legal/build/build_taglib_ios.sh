#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${PROJECT_DIR}/Build/TagLib"
OUTPUT_DIR="${PROJECT_DIR}/Vendor/TagLib"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-16.0}"

TAGLIB_SOURCE_DIR="${TAGLIB_SOURCE_DIR:-${PROJECT_DIR}/ThirdPartySources/taglib}"
EXPECTED_TAGLIB_REVISION="deadc2990767dfbda0701e0ab35fdeea653db08f"
EXPECTED_UTF8CPP_REVISION="2d8e20b22dcb3e9b3c4f52103182ebda949c6089"
UTF8CPP_SOURCE_DIR="${TAGLIB_SOURCE_DIR}/3rdparty/utfcpp"

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
  local sdk_name="$1"
  local archs="$2"
  local build_dir="${BUILD_ROOT}/${sdk_name}/build"
  local install_dir="${BUILD_ROOT}/${sdk_name}/install"

  local sdk_path
  sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"

  rm -rf "${build_dir}" "${install_dir}"
  mkdir -p "${build_dir}" "${install_dir}"

  cmake -S "${TAGLIB_SOURCE_DIR}" -B "${build_dir}" \
    -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="${sdk_path}" \
    -DCMAKE_OSX_ARCHITECTURES="${archs}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_IOS_VERSION}" \
    -DCMAKE_INSTALL_PREFIX="${install_dir}" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_BINDINGS=OFF \
    -DWITH_ZLIB=ON \
    -DWITH_MOD=OFF \
    -DWITH_SHORTEN=OFF

  cmake --build "${build_dir}" --config Release --parallel "$(sysctl -n hw.ncpu)"
  cmake --install "${build_dir}" --config Release
}

create_xcframework() {
  local device_library="${BUILD_ROOT}/iphoneos/install/lib/libtag.a"
  local simulator_library="${BUILD_ROOT}/iphonesimulator/install/lib/libtag.a"
  local output_path="${OUTPUT_DIR}/libtag.xcframework"

  if [[ ! -f "${device_library}" || ! -f "${simulator_library}" ]]; then
    echo "Could not find libtag.a for both slices" >&2
    exit 1
  fi

  rm -rf "${output_path}"
  xcodebuild -create-xcframework \
    -library "${device_library}" \
    -headers "${BUILD_ROOT}/iphoneos/install/include" \
    -library "${simulator_library}" \
    -headers "${BUILD_ROOT}/iphonesimulator/install/include" \
    -output "${output_path}"
}

require_dir "${TAGLIB_SOURCE_DIR}"
require_dir "${UTF8CPP_SOURCE_DIR}"
require_clean_source_revision taglib "${TAGLIB_SOURCE_DIR}" "${EXPECTED_TAGLIB_REVISION}"
require_clean_source_revision utfcpp "${UTF8CPP_SOURCE_DIR}" "${EXPECTED_UTF8CPP_REVISION}"

mkdir -p "${OUTPUT_DIR}"

build_cmake_slice iphoneos arm64
build_cmake_slice iphonesimulator "arm64;x86_64"

create_xcframework

cp "${TAGLIB_SOURCE_DIR}/COPYING.MPL" "${OUTPUT_DIR}/COPYING.MPL"
cp "${TAGLIB_SOURCE_DIR}/COPYING.LGPL" "${OUTPUT_DIR}/COPYING.LGPL"
cp "${UTF8CPP_SOURCE_DIR}/LICENSE" "${OUTPUT_DIR}/LICENSE.utfcpp"
{
  echo "taglib.source=https://github.com/taglib/taglib.git"
  echo "taglib.version=v2.3.2"
  echo "taglib.revision=${EXPECTED_TAGLIB_REVISION}"
  echo "taglib.modified=false"
  echo "taglib.license=MPL-1.1 (elected from MPL-1.1 / LGPL-2.1)"
  echo "taglib.build_options=BUILD_SHARED_LIBS=OFF BUILD_TESTING=OFF BUILD_EXAMPLES=OFF BUILD_BINDINGS=OFF WITH_ZLIB=ON WITH_MOD=OFF WITH_SHORTEN=OFF CMAKE_POSITION_INDEPENDENT_CODE=ON"
  echo "utfcpp.source=https://github.com/nemtrif/utfcpp.git"
  echo "utfcpp.version=v4.2.0"
  echo "utfcpp.revision=${EXPECTED_UTF8CPP_REVISION}"
  echo "utfcpp.modified=false"
  echo "utfcpp.license=BSL-1.0"
} > "${OUTPUT_DIR}/SOURCE_STATE.txt"

echo "TagLib is available under ${OUTPUT_DIR}"
