#!/bin/bash
set -euo pipefail

IMAGE="${IMAGE:-joedefen/ffmpeg-vaapi-docker}"
TAG="${TAG:-latest}"
if [[ -z "${VERSION:-}" ]]; then
    VERSION="$(date -u +%Y.%m.%d)-$(git rev-parse --short=7 HEAD 2>/dev/null || echo nogit)"
fi

set -x
docker build --pull -t "${IMAGE}:${TAG}" -t "${IMAGE}:${VERSION}" .
docker push "${IMAGE}:${TAG}"
docker push "${IMAGE}:${VERSION}"
set +x

echo "Successfully pushed ${IMAGE}:${TAG} and ${IMAGE}:${VERSION}"
