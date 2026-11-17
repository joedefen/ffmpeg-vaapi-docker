#!/bin/bash
set -euo pipefail

# Publish two tags: an immutable <date>-<commit> tag and a moving tag
# (TAG, "latest" by default). VERSION overrides the immutable tag name.

cd "$(dirname "$0")"

IMAGE="${IMAGE:-joedefen/ffmpeg-vaapi-docker}"
TAG="${TAG:-latest}"

# The immutable tag claims to describe a commit, so refuse to publish content
# that commit does not contain. Untracked files are harmless here:
# .dockerignore keeps tests/ and *.md out of the build context.
git_sha=""
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    git_sha="$(git rev-parse --short=7 HEAD)"
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "ERROR: the working tree has uncommitted changes." >&2
        echo "       A tag named after ${git_sha} would not describe what is published." >&2
        echo "       Commit or stash first:" >&2
        git status --short >&2
        exit 1
    fi
fi

if [[ -z "${VERSION:-}" ]]; then
    if [[ -z "${git_sha}" ]]; then
        echo "ERROR: not a git checkout, so no commit tag can be derived." >&2
        echo "       Set VERSION explicitly to publish from a tarball." >&2
        exit 1
    fi
    VERSION="$(date -u +%Y.%m.%d)-${git_sha}"
fi

# Build through build.sh so the architecture pre-flight and the label arguments
# are the same ones the local workflow uses.
IMAGE="${IMAGE}" TAG="${VERSION}" ./build.sh
docker tag "${IMAGE}:${VERSION}" "${IMAGE}:${TAG}"

# Never publish an image the smoke test rejects.
IMAGE_NAME="${IMAGE}:${VERSION}" ./test.sh

# Immutable tag first, moving tag last: if the second push fails, the moving tag
# still points at the last image that passed, never at a half-published one.
echo "Pushing ${IMAGE}:${VERSION}"
docker push "${IMAGE}:${VERSION}"
echo "Pushing ${IMAGE}:${TAG}"
docker push "${IMAGE}:${TAG}"

echo "Successfully pushed ${IMAGE}:${VERSION} (immutable) and ${IMAGE}:${TAG}"
