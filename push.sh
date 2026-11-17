#!/bin/bash
set -euo pipefail

IMAGE="${IMAGE:-joedefen/ffmpeg-vaapi-docker}"
TAG="${TAG:-latest}"
if [[ -z "${VERSION:-}" ]]; then
    VERSION="$(date -u +%Y.%m.%d)-$(git rev-parse --short=7 HEAD 2>/dev/null || echo nogit)"
fi

# Label values for the image metadata (see the LABEL block in the Dockerfile);
# the pushed image reports VERSION, not "dev".
build_args=(
    --build-arg "IMAGE_VERSION=${VERSION}"
    --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
)
if git rev-parse --short HEAD >/dev/null 2>&1; then
    build_args+=(--build-arg "GIT_REVISION=$(git rev-parse --short=12 HEAD)")
fi

set -x
docker build --pull -t "${IMAGE}:${TAG}" -t "${IMAGE}:${VERSION}" "${build_args[@]}" .
docker push "${IMAGE}:${TAG}"
docker push "${IMAGE}:${VERSION}"
set +x

echo "Successfully pushed ${IMAGE}:${TAG} and ${IMAGE}:${VERSION}"
