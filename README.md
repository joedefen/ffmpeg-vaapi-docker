# ffmpeg-vaapi-docker

FFmpeg with VA-API hardware acceleration for Intel Quick Sync and AMD graphics

## Overview

This Docker image provides FFmpeg with VA-API (Video Acceleration API) support,
enabling hardware-accelerated video encoding and decoding on Intel and AMD GPUs.
It is designed to work out-of-the-box on Linux systems with compatible hardware.

**It builds and runs on x86-64 Linux only** (`linux/amd64`). The Intel media
driver it depends on is not published for other architectures, so ARM hosts —
Apple Silicon, ARM servers, ARM NAS boxes — are out of scope. See
[Platform: amd64 only](#platform-amd64-only).

The image is based on Ubuntu 26.04 LTS and includes:
- FFmpeg from the Ubuntu 26.04 archive (8.0.1 at the time of writing, November 2026)
  with VA-API support; the exact version follows whatever the base image provides
- Intel Media VA driver (non-free)
- Intel VPL (Video Processing Library)
- VA-API verification tools

The image is about 840 MB and runs as an unprivileged user (uid 1000). Almost all
of that size is inherited from Ubuntu's own packaging rather than chosen here:
`libllvm21` (~132 MiB installed) and `mesa-libgallium` (~44 MiB) arrive through
FFmpeg's graphics dependencies, and the Intel media driver adds ~40 MiB. The Intel
driver is installed unconditionally, so the same image works on both Intel and AMD
hosts.

`mesa-va-drivers` is listed explicitly, but it is a virtual package name that
resolves to `mesa-libgallium`, which is already present; removing the line leaves
the image byte-for-byte the same size. It stays as a statement of intent.

## Purpose and Support Scope

This image has one job: give a personal video pipeline a predictable, working
`ffmpeg` with VA-API hardware H.265 encoding, instead of whatever the host happens
to have installed that week. It is published on Docker Hub only in case it spares
someone else the same trouble.

It is built and exercised for a deliberately narrow target:

- **one workload** — re-encoding to H.265/HEVC. Both `hevc_vaapi` (hardware) and
  `libx265` (software, present because Ubuntu builds FFmpeg with it) are
  available; the hardware path is the reason this image exists
- **one host class** — x86-64 Linux with an Intel GPU exposed through `/dev/dri`
- **one runtime** — Docker, with the container running as uid 1000

Everything outside that is best effort. There is no support, no roadmap, and no
promise about your particular GPU, driver, distribution or FFmpeg version. If it
works for you, that is a bonus; if it does not, this is a short Dockerfile and
three short scripts, so fixing it yourself is realistic. Issues and pull requests
may go unanswered.

The software is MIT licensed (see [`LICENSE`](LICENSE)), which carries no warranty
of any kind. Licences for the components redistributed inside the image are in
[`NOTICE`](NOTICE).

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

- **Non-x86-64 hosts** — ARM servers, Apple Silicon, ARM NAS boxes. The image is
  `linux/amd64` only, because no Intel media driver exists for other
  architectures (see [Platform: amd64 only](#platform-amd64-only))
- NVIDIA GPUs (use NVENC/NVDEC instead)
- Systems without integrated or discrete graphics
- Very old processors without hardware video acceleration

## Host System Requirements

1. **Linux kernel** with DRM (Direct Rendering Manager) support
2. **`/dev/dri/` device nodes** must be present (typically `/dev/dri/renderD128`)
3. **Permissions**: User must have access to `/dev/dri/` devices
   - Add user to `video` or `render` group: `sudo usermod -aG video,render "$USER"`
   - Or run Docker with appropriate privileges
4. **Docker** installed — this is the tested runtime. Podman probably works but is
   best effort and unverified (see [Podman](#podman-best-effort))
5. **An amd64 (x86-64) platform** — the image is built for `linux/amd64` only,
   because the Intel media driver is not published for other architectures
   (see [Platform: amd64 only](#platform-amd64-only))

### Platform: amd64 only

The image targets `linux/amd64` exclusively. `intel-media-va-driver-non-free` —
the iHD driver that makes Intel Quick Sync work — is published in Ubuntu's
`multiverse` component for `amd64` and for no other architecture. `ffmpeg`,
`vainfo`, `libvpl2` and Mesa are available for `arm64` as well, but without the
Intel driver the image would not do what its name says.

Both [`build.sh`](build.sh) and the [`Dockerfile`](Dockerfile) refuse to build for
any other architecture and explain why, rather than failing later inside `apt-get`
with a bare "Unable to locate package". On an arm64 host:

```text
$ uname -m
aarch64
$ ./build.sh
ERROR: this image targets linux/amd64 only; requested platform is 'linux/arm64'.
       'intel-media-va-driver-non-free' is not published for arm64.
       On an x86-64 host, omit --platform. To build under emulation anyway,
       pass --platform linux/amd64 deliberately.
```

A plain `docker build` is guarded too, at `RUN` time. Note that cross-building
`--platform linux/arm64` *from* an x86-64 host without emulation registered fails
one step earlier with `exec /bin/sh: exec format error`, because the guard itself
cannot execute; install binfmt support with
`docker run --privileged --rm tonistiigi/binfmt --install arm64` if you want to
cross-build.

Building under emulation (Apple Silicon, ARM servers) works but defeats the
purpose — there is no VA-API device to pass through, so you get a CPU-only
`ffmpeg` on a slow emulated layer:

```bash
docker build --platform linux/amd64 -t ffmpeg-vaapi-docker:latest .
```

### Podman (best effort)

Everything in this README is tested with Docker only. Podman is **untested and
unsupported**: there is no Podman installation on the machine this image is
developed on, so what follows is reasoned rather than verified.

The image is an ordinary Docker image and should run. Rootless Podman is where it
gets interesting — the container's `ubuntu` user (uid 1000) is mapped to a
subordinate uid, and supplementary groups such as `render` are not inherited
unless you ask:

```bash
podman run --rm \
    --device /dev/dri \
    --group-add keep-groups \
    -v "$(pwd)":/work:z -w /work \
    joedefen/ffmpeg-vaapi-docker:latest \
    -vaapi_device /dev/dri/renderD128 \
    -f lavfi -i testsrc=duration=1:size=640x480 \
    -vf format=nv12,hwupload -c:v hevc_vaapi -y out.mkv
```

- `--group-add keep-groups` (Podman 3.4+, cgroup v2) passes your own supplementary
  groups into the container, which is what grants access to the render node.
- `:z` relabels the bind mount for SELinux; it is harmless where SELinux is absent.
- `-w /work` is needed because the image defines no working directory of its own.
- [`test.sh`](test.sh) and the `.sh` helpers invoke `docker` directly and will not
  work under Podman.

The `ffmpeg` arguments above are the ones verified with Docker on the development
host; the Podman plumbing around them is not verified at all. If it does not work
out, use Docker.

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

If your host's render group has a different GID, pass it with `--group-add`.
The [Basic Usage](#basic-usage) example already does this — including the
fallback to 992 for hosts with no `render` group — so copy that line into any
example that lacks it:

```bash
--group-add "$(getent group render | cut -d: -f3 || echo 992)"
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
    --group-add "$(getent group render | cut -d: -f3 || echo 992)" \
    -v "$(pwd)":/workspace -w /workspace \
    joedefen/ffmpeg-vaapi-docker:latest \
    -i input.mp4 \
    -vaapi_device /dev/dri/renderD128 \
    -vf 'format=nv12,hwupload' \
    -c:v hevc_vaapi -qp 23 \
    output.mkv
```

`-vaapi_device` and `-vf format=nv12,hwupload` are not optional: the encoder needs
a device to talk to and only accepts frames that live on the GPU, so a software
input has to be converted and uploaded. Drop them and FFmpeg writes a zero-byte
file and reports `Conversion failed!`. See
[Why `format=nv12,hwupload`](#why-formatnv12hwupload).

`--group-add` passes your host's render GID into the container, falling back to
992 (the image's own `render` group) when the host has no `render` group. It is
not decoration: without the right GID the process cannot open the device. This
exact command shape is what [`test.sh`](test.sh) runs on every test, so it stays
honest.

**Output paths must be absolute, or `-w` must be set.** The image defines no
working directory, so the container starts in `/`, which uid 1000 cannot write to.
Without `-w`, a relative output path fails like this:

```text
[out#0/matroska @ 0x55ac57…] Error opening output out.mkv: Permission denied
Error opening output files: Permission denied
```

Either keep `-w /workspace` as above, or mount a volume and use absolute paths
inside it (`-v "$(pwd)":/workspace … /workspace/output.mkv`). The second form needs
no `-w`, which helps when input and output live in different directories.

### Compatibility with older rmbloat releases

[rmbloat](https://github.com/joedefen/rmbloat) is the pipeline this image was
built for. Releases up to 1.0.4 built their container command without naming
the binary — they passed the low-priority wrapper where the command belongs:

```text
docker run ... IMAGE ionice -c3 nice -n20 -y -progress pipe:2 ... -i in.mkv ...
```

With `ENTRYPOINT ["ffmpeg"]` (which every example here and rmbloat's probes
rely on) ffmpeg parsed `-c3` as its own option and exited with
`Unrecognized option 'c3'`; with no entry point at all the wrapper had no
ffmpeg to run.

The image's entry point is therefore a small shim that keeps both shapes
working:

- the exact legacy prefix `ionice -c3 nice -n20` gets the missing `ffmpeg`
  inserted after it, so rmbloat <= 1.0.4 works unchanged;
- anything that starts with an ffmpeg option, or that names its program
  explicitly, goes straight to `ffmpeg`.

rmbloat 1.0.5 and later choose the program with `--entrypoint` themselves, so
the shim is bypassed; `--entrypoint vainfo` and `--entrypoint ffprobe` behave
exactly as before, and no documented invocation changes.

The match is deliberately narrow: only that exact four-word prefix is
translated, and no arbitrary command is ever executed. The shim exists for
backwards compatibility and can be removed when 1.0.4 is no longer in use.

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
    -v "$(pwd)":/workspace \
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
    -v "$(pwd)":/workspace \
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
    -v "$(pwd)":/workspace \
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
---
---


## Building, Testing, Publishing
> Quick start:
```
git clone https://github.com/joedefen/ffmpeg-vaapi-docker.git
cd ffmpeg-vaapi-docker
./build.sh
./test.sh
./push.sh
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

### Pinning and refreshing the base image

The `FROM` line pins `ubuntu:26.04` to a fixed digest, so the base layers never
change unless someone edits the file. That is predictability, not byte-for-byte
reproducibility: the `RUN` layer installs unpinned package names, so `ffmpeg` and
the drivers follow whatever the archive serves on the day you build. That is how
security updates reach the image.

Nothing refreshes the digest automatically, so do it deliberately — monthly, or
when Ubuntu publishes a point release:

```bash
# 1. Read the tag's current digest
docker pull ubuntu:26.04
docker inspect ubuntu:26.04 --format '{{index .RepoDigests 0}}'
#    -> ubuntu@sha256:d66b366d...

# 2. Rewrite the FROM line in place (a no-op if the pin is already current)
digest="$(docker inspect ubuntu:26.04 --format '{{index .RepoDigests 0}}' | sed 's/^ubuntu@//')"
sed -i -E "s|^FROM ubuntu:26\.04@sha256:[0-9a-f]{64}$|FROM ubuntu:26.04@${digest}|" Dockerfile

# 3. Confirm the diff is exactly one changed digest, then rebuild and test
git diff Dockerfile
./build.sh && ./test.sh
```

If step 2 changes nothing, the pin is already current — note the check date in
your own records and move on. If it does change, commit the new digest on its own
so the base-image bump is individually reviewable.

### Testing a local build

[`test.sh`](test.sh) runs three things against an image already on the machine: a
synthetic 1080p null-source encode that proves the encoder works, the
[Basic Usage](#basic-usage) command itself against a real file in a temp
directory, checking that the output is non-empty and is the codec it expected,
and a compatibility pass that runs both the legacy command form used by rmbloat
<= 1.0.4 and the explicit `--entrypoint` form used from 1.0.5 on.
Three environment variables change what it does:

| Variable | Default | Effect |
| --- | --- | --- |
| `IMAGE_NAME` | `joedefen/ffmpeg-vaapi-docker:latest` | Image under test. Point it at a local build instead of a published tag. |
| `RENDER_DEV` | first `/dev/dri/renderD*` | Render node to test. Node numbering does not follow GPU order, so set this on multi-GPU hosts; when more than one node exists, the script lists them all and names the one it picked. |
| `DURATION` | `10` | Seconds of 1080p null-source to encode. Lower it for a quick check, raise it to hold the GPU under load. |

The encoder is taken from what `vainfo` advertises: `hevc_vaapi` when the GPU
reports a HEVC encoding entrypoint, otherwise `h264_vaapi` with a warning that
the image cannot serve its main use case (HEVC re-encoding) on that hardware.

```bash
./test.sh
IMAGE_NAME=ffmpeg-vaapi-docker:labels DURATION=1 ./test.sh
RENDER_DEV=/dev/dri/renderD129 ./test.sh
```

### Publishing

[`push.sh`](push.sh) publishes two tags: an immutable `YYYY.MM.DD.HH.MM-commit`
tag — UTC build time plus the 7-character sha, e.g.
`2026.11.17.02.40-48f6395` — and a moving tag (`TAG`, `latest` by default;
`VERSION` overrides the immutable name). It refuses to run unless `git status`
is completely empty: modified, staged and untracked files all count, because
both the tag name and the image's `org.opencontainers.image.version` label claim
to describe that commit, and they only mean something if nothing else was in the
build context. Only git-ignored paths such as `tmp/` may exist. It then builds
through [`build.sh`](build.sh) so the arch pre-flight and label arguments apply,
runs [`test.sh`](test.sh) on the result, and pushes the immutable tag first — so
a failure can never leave `latest` pointing at an untested image. Both scripts
honour `IMAGE` and `TAG`.

The image carries `/licenses/LICENSE` and `/licenses/NOTICE`, so a pulled copy
states the terms it is distributed under — the GPL source pointer for the FFmpeg
binaries and the non-free terms for the Intel driver — without sending anyone
back to GitHub. Package copyrights stay where dpkg puts them, under
`/usr/share/doc/<package>/copyright`.

#### Publishing with an SBOM and provenance

`push.sh` publishes with plain `docker build`/`docker push`, so it attaches no
attestations. If you want them, build and push with buildx instead:

```bash
docker buildx build \
    --sbom=true --provenance=true \
    --platform linux/amd64 \
    --push \
    -t joedefen/ffmpeg-vaapi-docker:latest .
```

The pushed tag then becomes an OCI index holding the image manifest plus an
attestation manifest: an SPDX-2.3 document (298 packages on the current base)
and SLSA provenance v1. Inspect with:

```bash
docker buildx imagetools inspect joedefen/ffmpeg-vaapi-docker:latest
```

`attestation-manifest` entries appear beside the `linux/amd64` image entry.
Verified with buildx v0.37 against a throwaway local registry.

---
---

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

Two different problems share this wording — check which one you have:

| Message mentions | Cause | Fix |
|---|---|---|
| `/dev/dri/renderD128`, `cannot open device` | group/GID access to the GPU | the steps above |
| `Error opening output <file>: Permission denied` | no `-w` and a relative output path, so FFmpeg tries to write to `/` | pass `-w`, or use an absolute path inside a mounted volume (see [Basic Usage](#basic-usage)) |

The second one has nothing to do with VA-API: the encode never starts, and the
message appears before any frames are processed.

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

Two different floors apply, and they are worth keeping apart:

- **Driver floor.** The image ships only Intel's iHD driver, which starts at
  Gen8 / Broadwell (2014). Older Intel graphics need the legacy i965 driver,
  which is not installed, so pre-Gen8 chips do not work with this image at all.
  On AMD the driver is Mesa's radeonsi, which covers GCN and newer.
- **Codec floor.** What the silicon can encode varies by generation and is
  independent of the driver.

Approximate, from vendor documentation (not measured on every generation here):

| Encoder | Intel (iHD) | AMD (radeonsi / Mesa) |
| --- | --- | --- |
| H.264 (AVC) | Gen8 / Broadwell (2014)+ | GCN-era (VCE) and newer |
| HEVC 8-bit | Skylake / Gen9 (2015)+ | VCN 1.0 / Vega (2017)+ |
| HEVC 10-bit | Kaby Lake / Gen9.5 (2017)+ | VCN 1.0+, per SKU |
| VP9 | Kaby Lake (2017)+, 8-bit, encode support is spotty | decode only — no VP9 encoder |
| AV1 | decode from Tiger Lake (Gen12); **encode only on Arc/DG2 and Meteor Lake+** — 11th gen is decode only | decode from RDNA 2; encode from RDNA 3 |

Two rows are the ones people get wrong: 11th-gen Intel has no AV1 *encoder*
(decode only), and VP9 encoding on Intel starts at Kaby Lake, not 9th gen.

`vainfo` inside the container is the ground truth for the machine you are on: it
lists `VAProfile*` next to `VAEntrypointEnc*`, and only `Enc` means encoding.
[`test.sh`](test.sh) reads the same output to choose which encoder to test.

Check your specific hardware for exact codec support.

## License

The repository's own files are MIT licensed - see [LICENSE](LICENSE).

The container image also redistributes third-party software, including the
non-free Intel media driver and a GPL-enabled FFmpeg build. The MIT license does
not cover those components; see [NOTICE](NOTICE) for the component list and the
GPL source-availability statement, and `/usr/share/doc/<package>/copyright`
inside the image for authoritative texts. Both files also ship inside the image
at `/licenses/LICENSE` and `/licenses/NOTICE`.

There is no warranty and no support commitment; see
[Purpose and Support Scope](#purpose-and-support-scope).

## Related Projects

- [FFmpeg](https://ffmpeg.org/)
- [libva](https://github.com/intel/libva)
- [intel-media-driver](https://github.com/intel/media-driver)

## Author

[joedefen](https://github.com/joedefen)