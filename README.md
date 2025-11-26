# ffmpeg-vaapi-docker

FFmpeg with VA-API hardware acceleration for Intel Quick Sync and AMD graphics

## Overview

This Docker image provides FFmpeg with VA-API (Video Acceleration API) support, enabling hardware-accelerated video encoding and decoding on Intel and AMD GPUs. It's designed to work out-of-the-box on Linux systems with compatible hardware.

The image is based on Ubuntu 25.10 and includes:
- FFmpeg 7.1+ with VA-API support
- Intel Media VA driver (non-free)
- Intel VPL (Video Processing Library)
- VA-API verification tools

## Hardware Requirements

### Supported Hardware

**Intel:**
- 4th generation Core processors (Haswell) or newer with integrated graphics
- Newer generations recommended for broader codec support (HEVC requires 6th gen+)
- Intel Arc discrete GPUs

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
    -v $(pwd):/workspace \
    -w /workspace \
    joedefen/ffmpeg-vaapi-docker:latest \
    -i input.mp4 \
    -c:v h264_vaapi \
    output.mp4
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

Test the build:

```bash
./test.sh
```

## Troubleshooting

### Permission Denied Errors

If you see permission errors accessing `/dev/dri/`:

```bash
# Add your user to the video and render groups
sudo usermod -aG video,render $USER

# Log out and back in, or run:
newgrp video
newgrp render
```

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

- **H.264 (AVC)**: Most Intel 4th gen+ and AMD APUs
- **HEVC (H.265)**: Intel 6th gen+ and newer AMD
- **VP9**: Intel 9th gen+ (limited support)
- **AV1**: Intel 11th gen+ (Arc GPUs), newer AMD

Check your specific hardware for exact codec support.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

## Related Projects

- [FFmpeg](https://ffmpeg.org/)
- [libva](https://github.com/intel/libva)
- [intel-media-driver](https://github.com/intel/media-driver)

## Author

[joedefen](https://github.com/joedefen)