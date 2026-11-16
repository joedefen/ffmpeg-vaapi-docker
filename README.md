# ffmpeg-vaapi-docker

FFmpeg with VA-API hardware acceleration for Intel Quick Sync and AMD graphics

## Overview

This Docker image provides FFmpeg with VA-API (Video Acceleration API) support, enabling hardware-accelerated video encoding and decoding on Intel and AMD GPUs. It's designed to work out-of-the-box on Linux systems with compatible hardware.

The image is based on Ubuntu 26.04 LTS and includes:
- FFmpeg from the Ubuntu 26.04 archive (8.0.1 at the time of writing, November 2026)
  with VA-API support; the exact version follows whatever the base image provides
- Intel Media VA driver (non-free)
- Intel VPL (Video Processing Library)
- VA-API verification tools

The image is about 840 MB and runs as an unprivileged user (uid 1000). The Intel
driver packages account for roughly 41 MB and are installed unconditionally, so
the same image works on both Intel and AMD hosts.

## Hardware Requirements

### Supported Hardware

**Intel:**
- 5th generation Core processors (Broadwell, general availability ~early 2015) or newer
  with integrated graphics — this image ships only the iHD driver, which starts at Gen8
- HEVC encoding requires 6th generation (Skylake, ~late 2015) or newer
- Newer generations recommended for broader codec support (AV1 encode needs 11th gen / Arc)
- Intel Arc discrete GPUs (Alchemist, ~2022)

**AMD:**
- APUs with integrated Vega or RDNA graphics
- Radeon discrete GPUs with VA-API support

### Unsupported Hardware

- NVIDIA GPUs (use NVENC/NVDEC instead)
- Systems without integrated or discrete graphics
- Very old processors without hardware video acceleration

## Host System Requirements

1. **Linux kernel** with DRM (Direct Rendering Manager) support
2. **`/dev/dri/` device nodes** must be present (typically `/dev/dri/renderD128`)
3. **Permissions**: User must have access to `/dev/dri/` devices
   - Add user to `video` or `render` group: `sudo usermod -aG video,render $USER`
   - Or run Docker with appropriate privileges
4. **Docker** or **Podman** installed

### Verify Your System

Check if hardware acceleration is available:

```bash
# Check for render devices
ls -l /dev/dri/

# Check permissions
groups
```

You should see devices like `renderD128`, `renderD129`, etc., and your user should be in the `video` or `render` group.

### Non-root user and device permissions

The container runs as uid/gid 1000 (`ubuntu`), which matches the first user on
most desktop Linux installs. For VA-API access it needs the host's render GID as
a supplementary group; the image already includes a `render` group with GID 992,
which matches most Debian/Ubuntu hosts.

If your host's render group has a different GID, add it to every `docker run`
command below:

```bash
--group-add "$(getent group render | cut -d: -f3)"
```

On SELinux hosts (Fedora, RHEL), also add `--security-opt label=disable`, and add
`:z` to bind mounts that the container must write to.

## Quick Start

### Pull the Image

```bash
docker pull joedefen/ffmpeg-vaapi-docker:latest
```

### Basic Usage

Run FFmpeg with hardware acceleration:

```bash
docker run --rm \
    --device=/dev/dri:/dev/dri \
    -v $(pwd):/workspace -w /workspace \
    joedefen/ffmpeg-vaapi-docker:latest \
    -i input.mp4 \
    -c:v hevc_vaapi -qp 23 \
    output.mkv
```

### Test Hardware Acceleration

Verify HEVC encoding works:

```bash
docker run --rm \
    --device=/dev/dri:/dev/dri \
    joedefen/ffmpeg-vaapi-docker:latest \
    -y \
    -init_hw_device vaapi=va:/dev/dri/renderD128 \
    -filter_hw_device va \
    -f lavfi -i nullsrc=s=128x128:d=1 \
    -vf 'format=nv12,hwupload' \
    -c:v hevc_vaapi \
    -frames:v 1 -f null -
```

If this completes without errors, hardware acceleration is working.

## Usage Examples

### H.264 Encoding

```bash
docker run --rm \
    --device=/dev/dri:/dev/dri \
    -v $(pwd):/workspace \
    -w /workspace \
    joedefen/ffmpeg-vaapi-docker:latest \
    -i input.mp4 \
    -vaapi_device /dev/dri/renderD128 \
    -vf 'format=nv12,hwupload' \
    -c:v h264_vaapi \
    -qp 23 \
    output.mp4
```

### HEVC (H.265) Encoding

```bash
docker run --rm \
    --device=/dev/dri:/dev/dri \
    -v $(pwd):/workspace \
    -w /workspace \
    joedefen/ffmpeg-vaapi-docker:latest \
    -i input.mp4 \
    -vaapi_device /dev/dri/renderD128 \
    -vf 'format=nv12,hwupload' \
    -c:v hevc_vaapi \
    -qp 25 \
    output.mp4
```

### Hardware Decoding + Encoding

```bash
docker run --rm \
    --device=/dev/dri:/dev/dri \
    -v $(pwd):/workspace \
    -w /workspace \
    joedefen/ffmpeg-vaapi-docker:latest \
    -hwaccel vaapi \
    -hwaccel_device /dev/dri/renderD128 \
    -hwaccel_output_format vaapi \
    -i input.mp4 \
    -c:v hevc_vaapi \
    output.mp4
```

### Check Available Hardware Accelerators

```bash
docker run --rm \
    --device=/dev/dri:/dev/dri \
    joedefen/ffmpeg-vaapi-docker:latest \
    -hwaccels
```

### Check VA-API Device Info

```bash
docker run --rm \
    --device=/dev/dri:/dev/dri \
    --entrypoint vainfo \
    joedefen/ffmpeg-vaapi-docker:latest
```

## Building Locally

Clone the repository:

```bash
git clone https://github.com/joedefen/ffmpeg-vaapi-docker.git
cd ffmpeg-vaapi-docker
```

Build the image:

```bash
./build.sh
# or manually:
docker build -t joedefen/ffmpeg-vaapi-docker:latest .
```

The base image is pinned by digest in the [`Dockerfile`](Dockerfile) for reproducible
builds. To pick up Ubuntu point releases and security updates, refresh the digest
deliberately:

```bash
docker pull ubuntu:26.04
docker inspect ubuntu:26.04 --format '{{index .RepoDigests 0}}'
# then update the FROM line in the Dockerfile
```

Test the build:

```bash
./test.sh
```

To publish, [`push.sh`](push.sh) builds with `--pull` and pushes both `latest`
and an immutable date+commit tag; set `VERSION` to override that tag. Both
scripts honour `IMAGE` and `TAG` environment variables.

## VA-API Details Worth Knowing

### Driver selection (`LIBVA_DRIVER_NAME`)

The image deliberately does not set `LIBVA_DRIVER_NAME`, so libva auto-detects:
`iHD` (intel-media-driver) on Intel, `radeonsi` (Mesa) on AMD. Auto-detection can
choose the wrong backend on hybrid or multi-GPU systems, or when another Intel
driver is present. Override it explicitly:

```bash
docker run --rm -e LIBVA_DRIVER_NAME=iHD \
    --device=/dev/dri:/dev/dri \
    --group-add "$(getent group render | cut -d: -f3)" \
    --entrypoint vainfo \
    joedefen/ffmpeg-vaapi-docker:latest
```

Use `LIBVA_DRIVER_NAME=radeonsi` on AMD. If `vainfo` reports no profiles, the
driver choice is the usual culprit.

### Why the "non-free" Intel driver

Ubuntu ships `intel-media-va-driver` (DFSG-free) and
`intel-media-va-driver-non-free`; the latter includes additional codec components
that do not meet Debian's free-software guidelines. This image uses the non-free
variant for broader codec coverage on Intel hardware.

### Bitrate and quality control (`-qp`, `-rc_mode`)

VA-API encoders default to constant QP. `-qp` takes 0-51 (lower is better; 20-25
is a reasonable starting point) and maps directly to the encoder's QP, so the
same value does not mean the same quality across codecs. For bitrate targeting,
pick a rate-control mode:

```bash
# Constant quality (default behaviour)
-c:v hevc_vaapi -rc_mode CQP -qp 24

# Variable bitrate with a target
-c:v hevc_vaapi -rc_mode VBR -b:v 6M -maxrate 8M

# Constant bitrate
-c:v hevc_vaapi -rc_mode CBR -b:v 6M
```

Not every mode is available for every codec and GPU; run
`ffmpeg -h encoder=hevc_vaapi` to see what the build supports.

### Why `format=nv12,hwupload`

VA-API encoders only accept GPU surfaces in NV12 (8-bit) or P010 (10-bit). When
decoding in software, frames live in system memory, so `format=nv12` converts
them and `hwupload` moves them to the GPU. With hardware decode
(`-hwaccel_output_format vaapi`) frames already live on the GPU and the upload
filter is unnecessary.

### Proving it is really accelerated

- Add `-v verbose` and look for the VA-API device FFmpeg opens.
- CPU usage should stay far below software `libx264`/`libx265` for the same
  input; compare with `docker stats` or `time`.
- `-benchmark` reports throughput; supported hardware should encode 1080p HEVC
  well above real time.
- `vainfo` is the ground truth: `VAEntrypointEnc*` means encoding is supported,
  while `VAEntrypointVLD` alone means decode only.

## Troubleshooting

### Permission Denied Errors

If you see permission errors accessing `/dev/dri/`:

```bash
# Add your user to the video and render groups
sudo usermod -aG video,render "$USER"
```

Group membership is only re-read at login, so log out and back in. To use the
new membership in the current shell without logging out, run a single command
with the group applied:

```bash
sg render -c 'vainfo'
```

If the container itself still cannot open the device, pass the host render GID:
`--group-add "$(getent group render | cut -d: -f3)"`.

### No Hardware Acceleration

If hardware acceleration isn't working:

1. Verify your hardware supports VA-API
2. Check that `/dev/dri/renderD128` exists
3. Try different render devices if you have multiple GPUs (`renderD129`, etc.)
4. Check `vainfo` output for errors

### Multiple GPUs

If you have multiple GPUs, you may need to specify the correct render device:

```bash
# List available devices
ls /dev/dri/

# Use specific device
docker run --rm \
    --device=/dev/dri:/dev/dri \
    joedefen/ffmpeg-vaapi-docker:latest \
    -vaapi_device /dev/dri/renderD129 \
    ...
```

## Performance Notes

Hardware acceleration typically provides:
- 3-5x faster encoding compared to software (x264/x265)
- Lower CPU usage
- Reduced power consumption
- Real-time encoding for high-resolution video

Quality may be slightly lower than software encoders at equivalent bitrates, but is generally excellent for most use cases.

## Codec Support

Codec support varies by hardware generation. Common codecs:

- **H.264 (AVC)**: Intel 5th gen+ (Broadwell/iHD) and AMD APUs
- **HEVC (H.265)**: Intel 6th gen+ (Skylake) and newer AMD
- **VP9**: Intel 9th gen+ (limited support) and RDNA+ AMD
- **AV1**: Intel 11th gen+ (Arc GPUs) and RDNA 3+ AMD

Check your specific hardware for exact codec support.

## License

The repository's own files are MIT licensed - see [LICENSE](LICENSE).

The container image also redistributes third-party software, including the
non-free Intel media driver and a GPL-enabled FFmpeg build. The MIT license does
not cover those components; see [NOTICE](NOTICE) for the component list, and
`/usr/share/doc/<package>/copyright` inside the image for authoritative texts.

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

## Related Projects

- [FFmpeg](https://ffmpeg.org/)
- [libva](https://github.com/intel/libva)
- [intel-media-driver](https://github.com/intel/media-driver)

## Author

[joedefen](https://github.com/joedefen)