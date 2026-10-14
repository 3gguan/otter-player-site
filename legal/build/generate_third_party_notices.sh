#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUMMARY_FILE="${PROJECT_DIR}/Compliance/THIRD_PARTY_SUMMARY.txt"
LICENSE_DIR="${PROJECT_DIR}/Compliance/Licenses"
OUTPUT_FILE="${PROJECT_DIR}/Compliance/THIRD_PARTY_NOTICES.txt"
CHECK_ONLY=0

if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=1
elif [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--check]" >&2
  exit 64
fi

required_files=(
  "${SUMMARY_FILE}"
  "${LICENSE_DIR}/FFmpeg-LICENSE.md"
  "${LICENSE_DIR}/LGPL-2.1.txt"
  "${LICENSE_DIR}/libsmb2-COPYING.txt"
  "${LICENSE_DIR}/libnfs-COPYING.txt"
  "${LICENSE_DIR}/libnfs-BSD-2-Clause.txt"
  "${LICENSE_DIR}/taglib-COPYING.MPL.txt"
  "${LICENSE_DIR}/utfcpp-LICENSE.txt"
  "${LICENSE_DIR}/pupnp-BSD-3-Clause.txt"
  "${LICENSE_DIR}/swift-nio-LICENSE.txt"
  "${LICENSE_DIR}/swift-nio-NOTICE.txt"
  "${LICENSE_DIR}/swift-nio-llhttp-MIT.txt"
  "${LICENSE_DIR}/swift-nio-uSHET-MIT.txt"
  "${LICENSE_DIR}/swift-nio-FreeBSD-SHA1-BSD-3-Clause.txt"
  "${LICENSE_DIR}/swift-atomics-LICENSE.txt"
  "${LICENSE_DIR}/swift-collections-LICENSE.txt"
  "${LICENSE_DIR}/swift-system-LICENSE.txt"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Missing required notice input: ${required_file}" >&2
    exit 1
  fi
done

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xplayer-notices.XXXXXX")"
trap 'rm -rf "${temp_dir}"' EXIT
generated_file="${temp_dir}/ThirdPartyNotices.txt"

append_file() {
  local title="$1"
  local source_file="$2"
  {
    printf '\n\n======================================================================\n'
    printf '%s\n' "${title}"
    printf '======================================================================\n\n'
    sed -n '1,$p' "${source_file}"
  } >> "${generated_file}"
}

sed -n '1,$p' "${SUMMARY_FILE}" > "${generated_file}"
append_file "FFmpeg upstream licensing overview" "${LICENSE_DIR}/FFmpeg-LICENSE.md"
append_file "GNU Lesser General Public License version 2.1" "${LICENSE_DIR}/LGPL-2.1.txt"
append_file "libsmb2 component licensing notice" "${LICENSE_DIR}/libsmb2-COPYING.txt"
append_file "libnfs component licensing notice" "${LICENSE_DIR}/libnfs-COPYING.txt"
append_file "libnfs generated RPC files - BSD 2-Clause License" "${LICENSE_DIR}/libnfs-BSD-2-Clause.txt"
append_file "pupnp - BSD 3-Clause License" "${LICENSE_DIR}/pupnp-BSD-3-Clause.txt"
append_file "TagLib - Mozilla Public License 1.1" "${LICENSE_DIR}/taglib-COPYING.MPL.txt"
append_file "utfcpp bundled in TagLib - Boost Software License 1.0" "${LICENSE_DIR}/utfcpp-LICENSE.txt"
append_file "SwiftNIO - Apache License 2.0" "${LICENSE_DIR}/swift-nio-LICENSE.txt"
append_file "SwiftNIO - NOTICE" "${LICENSE_DIR}/swift-nio-NOTICE.txt"
append_file "SwiftNIO embedded llhttp - MIT License" "${LICENSE_DIR}/swift-nio-llhttp-MIT.txt"
append_file "SwiftNIO embedded uSHET cpp_magic.h - MIT License" "${LICENSE_DIR}/swift-nio-uSHET-MIT.txt"
append_file "SwiftNIO embedded FreeBSD SHA-1 - BSD 3-Clause License" "${LICENSE_DIR}/swift-nio-FreeBSD-SHA1-BSD-3-Clause.txt"
append_file "Swift Atomics - Apache License 2.0 with Runtime Library Exception" "${LICENSE_DIR}/swift-atomics-LICENSE.txt"
append_file "Swift Collections - Apache License 2.0 with Runtime Library Exception" "${LICENSE_DIR}/swift-collections-LICENSE.txt"
append_file "Swift System - Apache License 2.0 with Runtime Library Exception" "${LICENSE_DIR}/swift-system-LICENSE.txt"

if [[ ${CHECK_ONLY} -eq 1 ]]; then
  if [[ ! -f "${OUTPUT_FILE}" ]] || ! cmp -s "${generated_file}" "${OUTPUT_FILE}"; then
    echo "Third-party notices are stale. Run Scripts/generate_third_party_notices.sh" >&2
    exit 1
  fi
  echo "Third-party notices are current."
  exit 0
fi

mkdir -p "$(dirname "${OUTPUT_FILE}")"
mv "${generated_file}" "${OUTPUT_FILE}"
echo "Wrote ${OUTPUT_FILE}"
