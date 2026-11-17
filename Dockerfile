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
# The Intel media driver (iHD) covers Gen8+ graphics; ~40 MB installed.
# ca-certificates is required if ffmpeg needs to pull via https.
# libvpl2 and libva-drm2 are hard dependencies of libavcodec62 and vainfo; they
# stay as explicit statements of intent.
# mesa-va-drivers is a virtual name for mesa-libgallium, the AMD (radeonsi)
# VA-API driver. apt installs it today anyway, by accident: the ffmpeg .deb
# depends on libsdl2-2.0-0 for ffplay, pulling libsdl2-classic -> libgbm1 ->
# mesa-libgallium -> libllvm21. Neither ffmpeg nor ffprobe links SDL. Listing
# mesa-va-drivers keeps AMD working if a future ffmpeg drops that dependency;
# deleting the line saves zero bytes today (measured: same image size). The
# driver plus its LLVM backend is ~176 MiB.
# Package versions are not pinned: each build takes the archive's current
# contents, security updates included.
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
#    (radeonsi, installed via mesa-va-drivers above), or the generic driver at
#    runtime.

# 3. Licence and notice files travel with the image, so a pulled copy states the
#    terms it is distributed under (GPL source pointer, non-free driver terms)
#    without sending anyone back to GitHub. Package copyrights stay where dpkg
#    puts them, under /usr/share/doc.
COPY NOTICE LICENSE /licenses/

# 4. Entry point.  The image exists to run ffmpeg, but rmbloat releases up to
#    1.0.4 put their low-priority wrapper where the command belongs and never
#    named the binary (``IMAGE ionice -c3 nice -n20 -y ...``), so a plain
#    ``ENTRYPOINT ["ffmpeg"]`` made ffmpeg parse ``-c3`` as its own option.
#    entrypoint.sh inserts the missing ``ffmpeg`` for that exact shape and
#    forwards everything else unchanged.
COPY entrypoint.sh /usr/local/bin/ffmpeg-entrypoint
RUN chmod 0755 /usr/local/bin/ffmpeg-entrypoint

# 5. Drop privileges. The Ubuntu base already provides the "ubuntu" user at
#    uid/gid 1000, which matches the first user on most desktop installs.
#    GID 992 is the common "render" GID on Debian/Ubuntu hosts; hosts that use
#    a different GID should pass --group-add "$(getent group render | cut -d: -f3)".
RUN groupadd --system --gid 992 render \
    && usermod -aG render ubuntu

USER ubuntu

# 6. Metadata. The base image carries Canonical's OCI labels ("ubuntu", "The
#    Ubuntu container image maintained by Canonical..."), which are wrong for
#    this image, so override them and record which base was used. The build
#    arguments are passed by build.sh and push.sh; the defaults apply to a bare
#    `docker build .`.
ARG IMAGE_VERSION="dev"
ARG GIT_REVISION="unknown"
ARG BUILD_DATE="unknown"
LABEL org.opencontainers.image.title="ffmpeg-vaapi-docker" \
      org.opencontainers.image.description="FFmpeg 8 with VA-API hardware encoding on Ubuntu 26.04 (Intel iHD and AMD Mesa drivers), linux/amd64 only" \
      org.opencontainers.image.url="https://github.com/joedefen/ffmpeg-vaapi-docker" \
      org.opencontainers.image.source="https://github.com/joedefen/ffmpeg-vaapi-docker" \
      org.opencontainers.image.documentation="https://github.com/joedefen/ffmpeg-vaapi-docker#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${GIT_REVISION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:26.04" \
      org.opencontainers.image.base.digest="sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db"

ENTRYPOINT ["/usr/local/bin/ffmpeg-entrypoint"]
CMD ["--help"]
