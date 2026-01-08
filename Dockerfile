# Use the Ubuntu 25.10 development codename, Questing Quokka
FROM ubuntu:questing

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