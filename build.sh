#!/bin/bash
set -euo pipefail

IMAGE="${IMAGE:-joedefen/ffmpeg-vaapi-docker}"
TAG="${TAG:-latest}"

# This image targets linux/amd64 only: intel-media-va-driver-non-free is not
# published for any other architecture. Check before calling Docker so the
# failure is about the architecture, not an opaque "Unable to locate package"
# (or an "exec format error" when cross-building without QEMU).
# Inspect the arguments for a platform request, but pass them all through
# untouched: the last --platform wins, here as well as in Docker.
args=("$@")
target_platform=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --platform=*) target_platform="${1#--platform=}" ;;
        --platform)   shift; target_platform="${1:-}" ;;
    esac
    shift
done

if [ -z "${target_platform}" ]; then
    target_platform="linux/$(docker version --format '{{.Server.Arch}}')"
fi

# Values such as "$BUILDPLATFORM" are resolved by Docker; leave those alone.
case "${target_platform}" in
    *'$'*) target_arch="" ;;
    *)     target_arch="${target_platform##*/}" ;;
esac

if [ -n "${target_arch}" ] && [ "${target_arch}" != "amd64" ]; then
    echo "ERROR: this image targets linux/amd64 only; requested platform is '${target_platform}'." >&2
    echo "       'intel-media-va-driver-non-free' is not published for ${target_arch}." >&2
    echo "       On an x86-64 host, omit --platform. To build under emulation anyway," >&2
    echo "       pass --platform linux/amd64 deliberately." >&2
    exit 1
fi

# Label values for the image metadata (see the LABEL block in the Dockerfile).
build_args=(
    --build-arg "IMAGE_VERSION=${TAG}"
    --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
)
if git rev-parse --short HEAD >/dev/null 2>&1; then
    build_args+=(--build-arg "GIT_REVISION=$(git rev-parse --short=12 HEAD)")
fi

set -x
docker build --pull -t "${IMAGE}:${TAG}" "${build_args[@]}" "${args[@]}" .
