#!/bin/bash
set -euo pipefail

IMAGE="${IMAGE:-joedefen/ffmpeg-vaapi-docker}"
TAG="${TAG:-latest}"

set -x
docker build --pull -t "${IMAGE}:${TAG}" "$@" .
