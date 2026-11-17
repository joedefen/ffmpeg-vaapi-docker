# Ubuntu 26.04 LTS (Resolute Raccoon). The base image is pinned to a fixed digest
# so its layers never change under you; see README, "Pinning and refreshing the
# base image", for how to move it forward deliberately. This is predictability,
# not byte-for-byte reproducibility: the apt packages installed below are not
# pinned and follow whatever the archive serves on the day you build.
FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db

# 0. Architecture guard. This image is linux/amd64 only, because
#    intel-media-va-driver-non-free is published for amd64 alone. Without this
#    check an arm64 build fails late inside apt-get with a confusing
#    "E: Unable to locate package" instead of saying why.
#    TARGETARCH is provided by BuildKit; fall back to the platform's own answer
#    for classic builders.
ARG TARGETARCH
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    if [ "$arch" != "amd64" ]; then \
        echo "ERROR: this image targets linux/amd64 only; build target is '$arch'." >&2; \
        echo "       'intel-media-va-driver-non-free' is not published for $arch." >&2; \
        echo "       To build under emulation anyway, add: --platform linux/amd64" >&2; \
        exit 1; \
    fi

# 1. Install drivers and runtime libraries.
# Intel-specific drivers (Alder Lake / 12th Gen+); ~41 MB installed.
# mesa-va-drivers keeps the image usable on AMD/Generic GPUs.
# libva-drm2 lets VA-API talk to the DRM (Direct Rendering Manager).
# ca-certificates is required if ffmpeg needs to pull via https.
# No package versions are pinned: each build picks up the current archive
# contents, including security updates for ffmpeg and the drivers.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ffmpeg \
        vainfo \
        intel-media-va-driver-non-free \
        libvpl2 \
        mesa-va-drivers \
        libva-drm2 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. No LIBVA_DRIVER_NAME is set: libva auto-detects Intel (iHD), AMD
#    (radeonsi), or the generic driver at runtime.

# 3. Drop privileges. The Ubuntu base already provides the "ubuntu" user at
#    uid/gid 1000, which matches the first user on most desktop installs.
#    GID 992 is the common "render" GID on Debian/Ubuntu hosts; hosts that use
#    a different GID should pass --group-add "$(getent group render | cut -d: -f3)".
RUN groupadd --system --gid 992 render \
    && usermod -aG render ubuntu

USER ubuntu

ENTRYPOINT ["ffmpeg"]
CMD ["--help"]
