# Use the Ubuntu 25.10 development codename, Questing Quokka
FROM ubuntu:questing
RUN apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    ffmpeg \
    vainfo \
    intel-media-va-driver-non-free \
    libvpl2 \
    libvpl-dev \
    && rm -rf /var/lib/apt/lists/*
# Set the default executable for running commands directly
ENTRYPOINT ["ffmpeg"]
CMD ["--help"]
