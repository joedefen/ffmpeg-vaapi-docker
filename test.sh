#!/bin/bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-joedefen/ffmpeg-vaapi-docker:latest}"
DURATION="${DURATION:-10}"
RENDER_DEV="${RENDER_DEV:-}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# Auto-detect a DRM render node unless the caller pinned one. Node numbering
# does not follow GPU order, so on multi-GPU hosts the lowest number is not
# necessarily the adapter you mean: list them all and say which one is used.
if [[ -z "${RENDER_DEV}" ]]; then
    shopt -s nullglob
    render_nodes=(/dev/dri/renderD*)
    shopt -u nullglob
    [[ ${#render_nodes[@]} -gt 0 ]] ||
        fail "no /dev/dri/renderD* devices found on the host; is the DRM driver loaded?"
    RENDER_DEV="${render_nodes[0]}"
    if [[ ${#render_nodes[@]} -gt 1 ]]; then
        printf 'Render nodes found: %s\n' "${render_nodes[*]}"
        printf 'Testing %s; re-run with RENDER_DEV to choose another.\n' "${RENDER_DEV}"
    fi
fi

[[ -e "${RENDER_DEV}" ]] || fail "${RENDER_DEV} does not exist"
[[ -r "${RENDER_DEV}" && -w "${RENDER_DEV}" ]] ||
    fail "${RENDER_DEV} is not readable/writable; add your user to the render group"

docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1 ||
    fail "image ${IMAGE_NAME} not found locally; run ./build.sh first"

printf 'Image:         %s\n' "${IMAGE_NAME}"
printf 'Render device: %s\n' "${RENDER_DEV}"
printf 'Duration:      %s\n' "${DURATION}"

RENDER_GID="$(stat -c '%g' "${RENDER_DEV}")"

printf '\n--- Checking VA-API Capabilities ---\n'
vainfo_out="$(docker run --rm \
    --device "${RENDER_DEV}:${RENDER_DEV}" \
    --group-add "${RENDER_GID}" \
    --entrypoint vainfo \
    "${IMAGE_NAME}")"
printf '%s\n' "${vainfo_out}"

grep -q '^vainfo: Driver version:' <<<"${vainfo_out}" ||
    fail "vainfo did not report a driver version"

# Encode capability varies by hardware generation, and the README documents
# cards (Intel Gen8/9, AMD Polaris) that encode H.264 but not HEVC. Test an
# encoder this GPU actually advertises instead of assuming HEVC.
if grep -Eq 'VAProfileHEVCMain[[:space:]]*:[[:space:]]*VAEntrypointEnc' <<<"${vainfo_out}"; then
    encoder=hevc_vaapi
elif grep -Eq 'VAProfileH264High[[:space:]]*:[[:space:]]*VAEntrypointEnc' <<<"${vainfo_out}"; then
    encoder=h264_vaapi
    printf '\nNote: this GPU advertises no HEVC encoder; testing H.264 instead.\n' >&2
    printf '      The image will not satisfy its main use case (HEVC re-encoding)\n' >&2
    printf '      on this hardware.\n' >&2
else
    fail "this GPU/driver advertises neither HEVC nor H.264 encoding entrypoints"
fi
expected_codec="${encoder%%_*}"

printf '\n--- Testing %s Hardware Encoding ---\n' "${encoder}"
docker run --rm \
    --device "${RENDER_DEV}:${RENDER_DEV}" \
    --group-add "${RENDER_GID}" \
    "${IMAGE_NAME}" \
    -hide_banner \
    -loglevel warning \
    -y \
    -init_hw_device "vaapi=va:${RENDER_DEV}" \
    -filter_hw_device va \
    -f lavfi -i "nullsrc=s=1920x1080:d=${DURATION}" \
    -vf 'format=nv12,hwupload' \
    -c:v "${encoder}" \
    -f null -

# Second pass: the README's "Basic Usage" example, as close to verbatim as a
# test can get. The arguments below the container name are copied from it —
# -i input.mp4, -vaapi_device, -vf format=nv12,hwupload, -qp 23, output.mkv —
# so if those flags stop working, this fails. Only the input generation and
# --user (so the output file is yours) are additions.
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

# The README passes the host's render GID and falls back to 992 when the host
# has no "render" group; use the same expression so both paths are exercised.
host_render_gid="$(getent group render | cut -d: -f3 || echo 992)"

printf '\n--- Testing the documented Basic Usage example ---\n'
docker run --rm \
    --device "${RENDER_DEV}:${RENDER_DEV}" \
    --group-add "${host_render_gid}" \
    --user "$(id -u):$(id -g)" \
    -v "${workdir}":/workspace \
    -w /workspace \
    "${IMAGE_NAME}" \
    -hide_banner -loglevel error \
    -f lavfi -i "testsrc=s=640x480:d=${DURATION}" \
    -c:v libx264 -preset ultrafast \
    input.mp4

docker run --rm \
    --device "${RENDER_DEV}:${RENDER_DEV}" \
    --group-add "${host_render_gid}" \
    --user "$(id -u):$(id -g)" \
    -v "${workdir}":/workspace \
    -w /workspace \
    "${IMAGE_NAME}" \
    -hide_banner -loglevel warning \
    -i input.mp4 \
    -vaapi_device "${RENDER_DEV}" \
    -vf 'format=nv12,hwupload' \
    -c:v "${encoder}" -qp 23 \
    output.mkv

[[ -s "${workdir}/output.mkv" ]] ||
    fail "the README's Basic Usage example wrote no output (missing or 0 bytes)"

actual_codec="$(docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "${workdir}":/workspace \
    --entrypoint ffprobe \
    "${IMAGE_NAME}" \
    -v error -select_streams v:0 -show_entries stream=codec_name \
    -of default=nw=1:nk=1 /workspace/output.mkv)"
[[ "${actual_codec}" == "${expected_codec}" ]] ||
    fail "the documented example produced '${actual_codec:-no video stream}', expected '${expected_codec}'"
printf 'Documented example output: %s, %s bytes\n' "${actual_codec}" \
    "$(stat -c %s "${workdir}/output.mkv")"

printf '\nAll VA-API checks passed (%s).\n' "${encoder}"
