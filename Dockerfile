# Ubuntu 26.04 LTS (Resolute Raccoon), 26.04.1; digest-pinned for reproducible builds (see README, "Building Locally")
FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db

# 1. Install drivers and runtime libraries.
# Intel-specific drivers (Alder Lake / 12th Gen+); ~41 MB installed.
# mesa-va-drivers keeps the image usable on AMD/Generic GPUs.
# libva-drm2 lets VA-API talk to the DRM (Direct Rendering Manager).
# ca-certificates is required if ffmpeg needs to pull via https.
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
