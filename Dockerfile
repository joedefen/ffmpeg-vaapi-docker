# Ubuntu 26.04 LTS (Resolute Raccoon), 26.04.1; digest-pinned for reproducible builds (see README, "Building Locally")
FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db

# 1. Install drivers and runtime libraries
RUN apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    ffmpeg \
    vainfo \
    # Intel-specific drivers (Alder Lake / 12th Gen+)
    intel-media-va-driver-non-free \
    libvpl2 \
    # AMD/Generic drivers (Ensures the image isn't "locked" to Intel)
    mesa-va-drivers \
    # Essential for VA-API to talk to the DRM (Direct Rendering Manager)
    libva-drm2 \
    # Standard SSL certs (required if ffmpeg needs to pull via https)
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. Environmental tweaks for hardware stability
# We don't hardcode LIBVA_DRIVER_NAME here so the system can auto-detect
# Intel (iHD) vs AMD (radeonsi) vs Generic.
ENV NVC_PROMPT_RELEASE=1

# 3. Setup the entrypoint
ENTRYPOINT ["ffmpeg"]
CMD ["--help"]