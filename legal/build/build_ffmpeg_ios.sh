#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG_SOURCE_DIR="${FFMPEG_SOURCE_DIR:-${PROJECT_DIR}/ThirdPartySources/FFmpeg}"
BUILD_ROOT="${PROJECT_DIR}/Build/FFmpeg"
OUTPUT_DIR="${PROJECT_DIR}/Vendor/FFmpeg"
STAGING_OUTPUT_DIR="${BUILD_ROOT}/VendorOutput"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-16.0}"
EXPECTED_FFMPEG_REVISION="9abe92e3af7fa7becc8f7f742b1457b4c28220a6"

LIBRARIES=(
  libavutil
  libavfilter
  libswresample
  libavcodec
  libavformat
)

COMMON_CONFIGURE_FLAGS=(
  --disable-programs
  --disable-doc
  --disable-debug
  --enable-small
  --disable-shared
  --enable-static
  --disable-everything
  --disable-avdevice
  --disable-postproc
  --disable-swscale
  --enable-network
  --disable-autodetect
  --enable-securetransport
  --enable-pic
  --enable-avcodec
  --enable-avformat
  --enable-avfilter
  --enable-avutil
  --enable-swresample
  --enable-filter=equalizer
  --enable-protocol=file
  --enable-protocol=http
  --enable-protocol=https
  --enable-protocol=httpproxy
  --enable-protocol=tcp
  --enable-protocol=tls
  --enable-demuxer=aac
  --enable-demuxer=ac3
  --enable-demuxer=aiff
  --enable-demuxer=amr
  --enable-demuxer=ape
  --enable-demuxer=asf
  --enable-demuxer=au
  --enable-demuxer=caf
  --enable-demuxer=dsf
  --enable-demuxer=dts
  --enable-demuxer=eac3
  --enable-demuxer=flac
  --enable-demuxer=matroska
  --enable-demuxer=mlp
  --enable-demuxer=mov
  --enable-demuxer=mp3
  --enable-demuxer=mpc
  --enable-demuxer=mpc8
  --enable-demuxer=ogg
  --enable-demuxer=oma
  --enable-demuxer=rm
  --enable-demuxer=tak
  --enable-demuxer=truehd
  --enable-demuxer=tta
  --enable-demuxer=w64
  --enable-demuxer=wav
  --enable-demuxer=wv
  --enable-parser=aac
  --enable-parser=aac_latm
  --enable-parser=ac3
  --enable-parser=dca
  --enable-parser=flac
  --enable-parser=mlp
  --enable-parser=mpegaudio
  --enable-parser=opus
  --enable-parser=tak
  --enable-parser=vorbis
  --enable-decoder=aac
  --enable-decoder=aac_fixed
  --enable-decoder=aac_latm
  --enable-decoder=ac3
  --enable-decoder=ac3_fixed
  --enable-decoder=alac
  --enable-decoder=als
  --enable-decoder=amrnb
  --enable-decoder=amrwb
  --enable-decoder=ape
  --enable-decoder=atrac3
  --enable-decoder=atrac3al
  --enable-decoder=atrac3p
  --enable-decoder=atrac3pal
  --enable-decoder=cook
  --enable-decoder=dca
  --enable-decoder=dsd_lsbf
  --enable-decoder=dsd_lsbf_planar
  --enable-decoder=dsd_msbf
  --enable-decoder=dsd_msbf_planar
  --enable-decoder=eac3
  --enable-decoder=flac
  --enable-decoder=mlp
  --enable-decoder=mp1
  --enable-decoder=mp1float
  --enable-decoder=mp2
  --enable-decoder=mp2float
  --enable-decoder=mp3
  --enable-decoder=mp3adu
  --enable-decoder=mp3adufloat
  --enable-decoder=mp3float
  --enable-decoder=mp3on4
  --enable-decoder=mp3on4float
  --enable-decoder=mpc7
  --enable-decoder=mpc8
  --enable-decoder=opus
  --enable-decoder=pcm_alaw
  --enable-decoder=pcm_bluray
  --enable-decoder=pcm_dvd
  --enable-decoder=pcm_f16le
  --enable-decoder=pcm_f24le
  --enable-decoder=pcm_f32be
  --enable-decoder=pcm_f32le
  --enable-decoder=pcm_f64be
  --enable-decoder=pcm_f64le
  --enable-decoder=pcm_lxf
  --enable-decoder=pcm_mulaw
  --enable-decoder=pcm_s16be
  --enable-decoder=pcm_s16be_planar
  --enable-decoder=pcm_s16le
  --enable-decoder=pcm_s16le_planar
  --enable-decoder=pcm_s24be
  --enable-decoder=pcm_s24daud
  --enable-decoder=pcm_s24le
  --enable-decoder=pcm_s24le_planar
  --enable-decoder=pcm_s32be
  --enable-decoder=pcm_s32le
  --enable-decoder=pcm_s32le_planar
  --enable-decoder=pcm_s64be
  --enable-decoder=pcm_s64le
  --enable-decoder=pcm_s8
  --enable-decoder=pcm_s8_planar
  --enable-decoder=pcm_u16be
  --enable-decoder=pcm_u16le
  --enable-decoder=pcm_u24be
  --enable-decoder=pcm_u24le
  --enable-decoder=pcm_u32be
  --enable-decoder=pcm_u32le
  --enable-decoder=pcm_u8
  --enable-decoder=ra_144
  --enable-decoder=ra_288
  --enable-decoder=sipr
  --enable-decoder=tak
  --enable-decoder=truehd
  --enable-decoder=tta
  --enable-decoder=vorbis
  --enable-decoder=wavpack
  --enable-decoder=wmalossless
  --enable-decoder=wmapro
  --enable-decoder=wmav1
  --enable-decoder=wmav2
)

require_config_enabled() {
  local config_file="$1"
  local config_name="$2"

  if ! grep -q "^#define ${config_name} 1$" "${config_file}"; then
    echo "Required FFmpeg feature ${config_name} is disabled in ${config_file}" >&2
    exit 1
  fi
}

require_config_disabled() {
  local config_file="$1"
  local config_name="$2"

  if ! grep -q "^#define ${config_name} 0$" "${config_file}"; then
    echo "Forbidden FFmpeg feature ${config_name} is enabled in ${config_file}" >&2
    exit 1
  fi
}

require_clean_source_revision() {
  local actual_revision
  actual_revision="$(git -C "${FFMPEG_SOURCE_DIR}" rev-parse HEAD)"
  if [[ "${actual_revision}" != "${EXPECTED_FFMPEG_REVISION}" ]]; then
    echo "FFmpeg revision ${actual_revision} does not match ${EXPECTED_FFMPEG_REVISION}" >&2
    exit 1
  fi
  if [[ -n "$(git -C "${FFMPEG_SOURCE_DIR}" status --porcelain --untracked-files=all)" ]]; then
    echo "FFmpeg source checkout is dirty; update the manifest and patch workflow before building" >&2
    exit 1
  fi
}

build_slice() {
  local sdk_name="$1"
  local platform="$2"
  local arch="$3"
  local slice_name="$4"
  local build_dir="${BUILD_ROOT}/${slice_name}/build"
  local install_dir="${BUILD_ROOT}/${slice_name}/install"
  local sdk_path
  local cc
  local extra_configure_flag=""

  sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
  cc="$(xcrun --sdk "${sdk_name}" --find clang)"

  if [[ "${arch}" == "x86_64" ]]; then
    extra_configure_flag="--disable-x86asm"
  fi

  rm -rf "${build_dir}" "${install_dir}"
  mkdir -p "${build_dir}" "${install_dir}"

  pushd "${build_dir}" >/dev/null
  "${FFMPEG_SOURCE_DIR}/configure" \
    --prefix="${install_dir}" \
    --target-os=darwin \
    --arch="${arch}" \
    --cc="${cc}" \
    --sysroot="${sdk_path}" \
    --enable-cross-compile \
    --extra-cflags="-arch ${arch} -isysroot ${sdk_path} -m${platform}-version-min=${MIN_IOS_VERSION}" \
    --extra-ldflags="-arch ${arch} -isysroot ${sdk_path} -m${platform}-version-min=${MIN_IOS_VERSION}" \
    "${COMMON_CONFIGURE_FLAGS[@]}" \
    ${extra_configure_flag:+"${extra_configure_flag}"}

  require_config_enabled "${build_dir}/config.h" CONFIG_NETWORK
  require_config_enabled "${build_dir}/config.h" CONFIG_SECURETRANSPORT
  require_config_enabled "${build_dir}/config_components.h" CONFIG_HTTP_PROTOCOL
  require_config_enabled "${build_dir}/config_components.h" CONFIG_HTTPS_PROTOCOL
  require_config_enabled "${build_dir}/config_components.h" CONFIG_TCP_PROTOCOL
  require_config_enabled "${build_dir}/config_components.h" CONFIG_TLS_PROTOCOL
  for disabled_config in \
    CONFIG_GPL \
    CONFIG_NONFREE \
    CONFIG_VERSION3 \
    CONFIG_LIBSMBCLIENT \
    CONFIG_OPENSSL \
    CONFIG_LIBX264 \
    CONFIG_LIBX265; do
    require_config_disabled "${build_dir}/config.h" "${disabled_config}"
  done

  make -j"$(sysctl -n hw.ncpu)"
  make install
  popd >/dev/null
}

create_xcframework() {
  local library_name="$1"
  local device_install="${BUILD_ROOT}/iphoneos-arm64/install"
  local simulator_arm64_install="${BUILD_ROOT}/iphonesimulator-arm64/install"
  local simulator_x86_64_install="${BUILD_ROOT}/iphonesimulator-x86_64/install"
  local simulator_universal_dir="${BUILD_ROOT}/iphonesimulator-universal"
  local device_headers="${BUILD_ROOT}/headers/iphoneos-arm64/${library_name}"
  local simulator_headers="${BUILD_ROOT}/headers/iphonesimulator-universal/${library_name}"
  local output_path="${STAGING_OUTPUT_DIR}/${library_name}.xcframework"

  rm -rf "${simulator_universal_dir}" "${device_headers}" "${simulator_headers}"
  mkdir -p "${simulator_universal_dir}/lib" "${device_headers}" "${simulator_headers}"

  lipo -create \
    "${simulator_arm64_install}/lib/${library_name}.a" \
    "${simulator_x86_64_install}/lib/${library_name}.a" \
    -output "${simulator_universal_dir}/lib/${library_name}.a"

  cp -R "${device_install}/include/${library_name}" "${device_headers}/${library_name}"
  cp -R "${simulator_arm64_install}/include/${library_name}" "${simulator_headers}/${library_name}"

  rm -rf "${output_path}"
  xcodebuild -create-xcframework \
    -library "${device_install}/lib/${library_name}.a" \
    -headers "${device_headers}" \
    -library "${simulator_universal_dir}/lib/${library_name}.a" \
    -headers "${simulator_headers}" \
    -output "${output_path}"
}

main() {
  if [[ ! -x "${FFMPEG_SOURCE_DIR}/configure" ]]; then
    echo "FFmpeg configure not found at ${FFMPEG_SOURCE_DIR}" >&2
    exit 1
  fi

  require_clean_source_revision

  rm -rf "${STAGING_OUTPUT_DIR}"
  mkdir -p "${BUILD_ROOT}" "${STAGING_OUTPUT_DIR}"

  build_slice iphoneos iphoneos arm64 iphoneos-arm64
  build_slice iphonesimulator ios-simulator arm64 iphonesimulator-arm64
  build_slice iphonesimulator ios-simulator x86_64 iphonesimulator-x86_64

  for library_name in "${LIBRARIES[@]}"; do
    create_xcframework "${library_name}"
  done

  cp "${FFMPEG_SOURCE_DIR}/LICENSE.md" "${STAGING_OUTPUT_DIR}/LICENSE.md"
  cp "${FFMPEG_SOURCE_DIR}/COPYING.LGPLv2.1" "${STAGING_OUTPUT_DIR}/COPYING.LGPLv2.1"
  mkdir -p "${STAGING_OUTPUT_DIR}/BuildConfiguration"
  for slice_name in iphoneos-arm64 iphonesimulator-arm64 iphonesimulator-x86_64; do
    mkdir -p "${STAGING_OUTPUT_DIR}/BuildConfiguration/${slice_name}"
    cp "${BUILD_ROOT}/${slice_name}/build/config.h" "${STAGING_OUTPUT_DIR}/BuildConfiguration/${slice_name}/config.h"
    cp "${BUILD_ROOT}/${slice_name}/build/config_components.h" "${STAGING_OUTPUT_DIR}/BuildConfiguration/${slice_name}/config_components.h"
    cp "${BUILD_ROOT}/${slice_name}/build/ffbuild/config.mak" "${STAGING_OUTPUT_DIR}/BuildConfiguration/${slice_name}/config.mak"
  done
  {
    echo "source=https://github.com/FFmpeg/FFmpeg.git"
    echo "version=n7.1.4"
    echo "revision=${EXPECTED_FFMPEG_REVISION}"
    echo "modified=false"
  } > "${STAGING_OUTPUT_DIR}/SOURCE_STATE.txt"

  rm -rf "${OUTPUT_DIR}"
  mv "${STAGING_OUTPUT_DIR}" "${OUTPUT_DIR}"

  echo "FFmpeg iOS XCFrameworks written to ${OUTPUT_DIR}"
}

main "$@"
