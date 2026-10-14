#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${1:-${ROOT_DIR}/ThirdPartySources/pupnp}"
OUTPUT_DIR="${ROOT_DIR}/Vendor/PUPnP"
XCFRAMEWORK_PATH="${OUTPUT_DIR}/pupnp.xcframework"
DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-16.0}"
EXPECTED_REVISION="4145da68112f61660c8e55ed61fae1bb07d0e3d8"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xplayer-pupnp.XXXXXX")"
WORKING_SOURCE="${BUILD_ROOT}/source"

cleanup() {
    rm -rf "${BUILD_ROOT}"
}
trap cleanup EXIT

if [[ ! -f "${SOURCE_DIR}/CMakeLists.txt" || ! -f "${SOURCE_DIR}/COPYING" ]]; then
    echo "pupnp source not found at ${SOURCE_DIR}" >&2
    exit 1
fi
if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
    echo "pupnp source is not a Git checkout: ${SOURCE_DIR}" >&2
    exit 1
fi
source_revision="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
if [[ "${source_revision}" != "${EXPECTED_REVISION}" ]]; then
    echo "pupnp revision is ${source_revision}, expected ${EXPECTED_REVISION}" >&2
    exit 1
fi
if [[ -n "$(git -C "${SOURCE_DIR}" status --porcelain --untracked-files=all)" ]]; then
    echo "pupnp source checkout contains uncommitted files: ${SOURCE_DIR}" >&2
    exit 1
fi

mkdir -p "${WORKING_SOURCE}"
rsync -a --exclude .git "${SOURCE_DIR}/" "${WORKING_SOURCE}/"

# pupnp 22.0.4 splits this generator expression across list elements, which
# CMake 4 rejects. Keep the upstream checkout untouched and normalize the
# expression only in this disposable build copy.
perl -0pi -e 's/\$<OR:\$<BOOL:\$\{UPNP_ENABLE_GENA\}>,\s*\$<BOOL:\$\{UPNP_ENABLE_OPTIONAL_SSDP_HEADERS\}>>/\$<OR:\$<BOOL:\$\{UPNP_ENABLE_GENA\}>,\$<BOOL:\$\{UPNP_ENABLE_OPTIONAL_SSDP_HEADERS\}>>/g' \
    "${WORKING_SOURCE}/upnp/CMakeLists.txt"

build_slice() {
    local name="$1"
    local sdk="$2"
    local architectures="$3"
    local build_dir="${BUILD_ROOT}/${name}"

    cmake -S "${WORKING_SOURCE}" -B "${build_dir}" -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="${sdk}" \
        -DCMAKE_OSX_ARCHITECTURES="${architectures}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        -DUPNP_BUILD_SHARED=OFF \
        -DUPNP_BUILD_STATIC=ON \
        -DUPNP_BUILD_SAMPLES=OFF \
        -DUPNP_ENABLE_TESTING=OFF \
        -DUPNP_ENABLE_TESTING_INTEGRATION=OFF \
        -DUPNP_ENABLE_CLIENT_API=ON \
        -DUPNP_ENABLE_DEVICE_API=OFF \
        -DUPNP_ENABLE_SOAP=ON \
        -DUPNP_ENABLE_SSDP=ON \
        -DUPNP_ENABLE_WEBSERVER=OFF \
        -DUPNP_ENABLE_GENA=OFF \
        -DUPNP_ENABLE_BACKTRACE=OFF \
        -DUPNP_ENABLE_OPEN_SSL=OFF \
        -DUPNP_ENABLE_IPV6=ON

    cmake --build "${build_dir}" --target upnp_static ixml_static --parallel
    xcrun libtool -static \
        -o "${BUILD_ROOT}/libpupnp-${name}.a" \
        "${build_dir}/upnp/libupnp.a" \
        "${build_dir}/ixml/libixml.a"
}

build_slice "ios-arm64" "iphoneos" "arm64"
build_slice "ios-simulator" "iphonesimulator" "arm64;x86_64"

HEADERS_DIR="${BUILD_ROOT}/headers/upnp"
mkdir -p "${HEADERS_DIR}"
cp "${WORKING_SOURCE}"/upnp/inc/*.h "${HEADERS_DIR}/"
cp "${WORKING_SOURCE}"/ixml/inc/*.h "${HEADERS_DIR}/"
cp "${BUILD_ROOT}/ios-arm64/upnp/inc/upnpconfig.h" "${HEADERS_DIR}/upnpconfig.h"

mkdir -p "${OUTPUT_DIR}"
rm -rf "${XCFRAMEWORK_PATH}"
xcodebuild -create-xcframework \
    -library "${BUILD_ROOT}/libpupnp-ios-arm64.a" \
    -headers "${BUILD_ROOT}/headers" \
    -library "${BUILD_ROOT}/libpupnp-ios-simulator.a" \
    -headers "${BUILD_ROOT}/headers" \
    -output "${XCFRAMEWORK_PATH}"

cp "${SOURCE_DIR}/COPYING" "${OUTPUT_DIR}/COPYING.pupnp"
source_version="$(sed -n 's/^[[:space:]]*VERSION \([0-9][0-9.]*\)$/\1/p' "${SOURCE_DIR}/CMakeLists.txt" | head -1)"
printf 'source=%s\nrevision=%s\nversion=%s\ndeployment_target=%s\n' \
    "${SOURCE_DIR}" "${source_revision}" "${source_version:-unknown}" "${DEPLOYMENT_TARGET}" \
    > "${OUTPUT_DIR}/SOURCE_STATE.txt"

echo "Created ${XCFRAMEWORK_PATH}"
