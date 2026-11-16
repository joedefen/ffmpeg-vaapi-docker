#!/bin/bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-joedefen/ffmpeg-vaapi-docker:latest}"
DURATION="${DURATION:-10}"
RENDER_DEV="${RENDER_DEV:-}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# Auto-detect the first DRM render node unless the caller pinned one.
if [[ -z "${RENDER_DEV}" ]]; then
    shopt -s nullglob
    render_nodes=(/dev/dri/renderD*)
    shopt -u nullglob
    [[ ${#render_nodes[@]} -gt 0 ]] ||
        fail "no /dev/dri/renderD* devices found on the host; is the DRM driver loaded?"
    RENDER_DEV="${render_nodes[0]}"
fi

[[ -e "${RENDER_DEV}" ]] || fail "${RENDER_DEV} does not exist"
[[ -r "${RENDER_DEV}" && -w "${RENDER_DEV}" ]] ||
    fail "${RENDER_DEV} is not readable/writable; add your user to the render group"

docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1 ||
    fail "image ${IMAGE_NAME} not found locally; run ./build.sh first"

printf 'Image:         %s\n' "${IMAGE_NAME}"
printf 'Render device: %s\n' "${RENDER_DEV}"
printf 'Duration:      %s\n' "${DURATION}"

printf '\n--- Checking VA-API Capabilities ---\n'
vainfo_out="$(docker run --rm \
    --device "${RENDER_DEV}:${RENDER_DEV}" \
    --entrypoint vainfo \
    "${IMAGE_NAME}")"
printf '%s\n' "${vainfo_out}"

grep -q '^vainfo: Driver version:' <<<"${vainfo_out}" ||
    fail "vainfo did not report a driver version"

grep -q 'VAProfileHEVCMain' <<<"${vainfo_out}" ||
    fail "this GPU/driver does not advertise HEVC support"

grep -Eq 'VAProfileHEVCMain[[:space:]]*:[[:space:]]*VAEntrypointEnc' <<<"${vainfo_out}" ||
    fail "this GPU/driver does not advertise HEVC encoding (only decoding)"

printf '\n--- Testing HEVC Hardware Encoding ---\n'
docker run --rm \
    --device "${RENDER_DEV}:${RENDER_DEV}" \
    "${IMAGE_NAME}" \
    -hide_banner \
    -loglevel warning \
    -y \
    -init_hw_device "vaapi=va:${RENDER_DEV}" \
    -filter_hw_device va \
    -f lavfi -i "nullsrc=s=1920x1080:d=${DURATION}" \
    -vf 'format=nv12,hwupload' \
    -c:v hevc_vaapi \
    -f null -

printf '\nAll VA-API checks passed.\n'
