# ffmpeg-vaapi-docker

FFmpeg with VA-API hardware acceleration for Intel Quick Sync and AMD graphics

## Why this container

A host's `ffmpeg` is a lottery: whichever distribution, third-party repository or base image is installed decides what the binary can do, and the failures look alike — `No VA display found`, `Decoder (hevc) not found`, `Unknown encoder 'hevc_vaapi'`. This image pins a current, fully featured ffmpeg plus everything VA-API needs, and behaves the same on every amd64 host.

- **VA-API is a build-time choice.** It is off unless libva headers were present at configure time. Minimal images, static builds and lesser-known distributions omit it; no runtime package adds it back.
- **QSV depends on a moving target.** `--enable-libvpl` exists from FFmpeg 5.0; earlier builds used `--enable-libmfx`, which Intel retired in 2023.
- **Some distributions strip codecs.** Fedora's `ffmpeg-free` lacks H.264 and HEVC without RPM Fusion, openSUSE needs Packman, and the RHEL family ships no ffmpeg.
- **The VA driver is a separate, sometimes non-free package.** iHD is in Ubuntu multiverse but not Debian main; AMD's driver is `mesa-va-drivers` on Debian and Ubuntu and named differently elsewhere; minimal images pull in neither. A correctly built ffmpeg still fails without it.
- **Distribution versions lag.** Debian stable freezes for about two years, while VA-API capability keeps arriving: 10-bit HEVC, AV1, rate-control modes, new filters, driver fixes.
- **One artifact for both vendors.** FFmpeg, iHD, radeonsi and VPL pinned together: the same command works on an Intel laptop and an AMD desktop.

## Overview

FFmpeg with VA-API (Video Acceleration API) on Intel Quick Sync and AMD graphics, based on Ubuntu 26.04 LTS:

- FFmpeg from the Ubuntu 26.04 archive (8.0.1 in November 2026), following the base image's version
- Intel Media VA driver (non-free)
- Intel VPL (Video Processing Library)
- `vainfo`

It runs as uid 1000 and is about 840 MB. Most of that is Ubuntu's own packaging: `libllvm21` (~132 MiB) and `mesa-libgallium` (~44 MiB) arrive with FFmpeg's graphics libraries, and the Intel driver adds ~40 MiB. x86-64 only — see [Platform: amd64 only](#platform-amd64-only).

That 176 MiB Mesa/LLVM block is the cost of AMD support. `mesa-libgallium` is the radeonsi VA-API driver, and apt would install it today regardless: the `ffmpeg` package depends on `libsdl2-2.0-0` for `ffplay`, which pulls `libsdl2-classic` → `libgbm1` → `mesa-libgallium` → `libllvm21`. Neither `ffmpeg` nor `ffprobe` links SDL, so the chain is an accident of shipping the player. The explicit `mesa-va-drivers` line keeps AMD working if a future ffmpeg drops that dependency; deleting it changes the image by zero bytes today (measured).

## Purpose and Support Scope

Built and exercised for a deliberately narrow target:

- **one workload** — H.265/HEVC re-encoding; both `hevc_vaapi` (hardware) and `libx265` (software) are available
- **one host class** — x86-64 Linux with an Intel GPU on `/dev/dri`
- **one runtime** — Docker, running as uid 1000

Outside that, best effort: no support, no roadmap.

## Hardware Requirements

### Supported Hardware

**Intel:**
- Broadwell (5th gen, 2015) or newer with integrated graphics
- HEVC encoding needs Skylake (6th gen, 2015); AV1 encode needs 11th gen or Arc
- Intel Arc discrete GPUs (Alchemist, 2022)

**AMD:**
- APUs with Vega or RDNA graphics
- Radeon discrete GPUs with VA-API support

### Unsupported Hardware

- Non-x86-64 hosts
- NVIDIA GPUs (use NVENC/NVDEC)
- Systems without integrated or discrete graphics, or too old for hardware video acceleration

## Host System Requirements

1. **Linux kernel** with DRM support
2. **`/dev/dri/` nodes** present (typically `/dev/dri/renderD128`)
3. **Access to them** — add your user to the `video` or `render` group: `sudo usermod -aG video,render "$USER"`
4. **Docker** — the tested runtime; Podman is unverified (see [Podman](#podman-best-effort))
5. **An amd64 host** (see [Platform: amd64 only](#platform-amd64-only))

### Non-root user and device permissions

The container runs as uid/gid 1000 (`ubuntu`). VA-API access needs the host's render GID as a supplementary group; the image has a `render` group with GID 992, matching most Debian/Ubuntu hosts.

If your host's GID differs, pass it — the [Basic Usage](#basic-usage) command already does:

```bash
--group-add "$(getent group render | cut -d: -f3 || echo 992)"
```

On SELinux hosts (Fedora, RHEL) also add `--security-opt label=disable`, and `:z` to bind mounts the container writes to.

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

`-vaapi_device` and `-vf format=nv12,hwupload` are not optional: the encoder needs a device, and accepts only frames resident on the GPU, so software input must be converted and uploaded. Without them FFmpeg writes a zero-byte file and reports `Conversion failed!` — see [Why `format=nv12,hwupload`](#why-formatnv12hwupload).

`--group-add` passes the host render GID, falling back to 992 (the image's own `render` group); without the right GID the process cannot open the device. [`test.sh`](test.sh) runs this exact command shape.

**Output paths must be absolute, or `-w` must be set.** The image defines no working directory, so the container starts in `/`, which uid 1000 cannot write to:

```text
[out#0/matroska @ 0x55ac57…] Error opening output out.mkv: Permission denied
Error opening output files: Permission denied
```

Either keep `-w /workspace`, or mount a volume and use absolute paths inside it (`-v "$(pwd)":/workspace … /workspace/output.mkv`); the second form needs no `-w`, which helps when input and output live elsewhere.

### Test Hardware Acceleration

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

No errors means acceleration works.

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

## Building, Testing, Publishing

```bash
git clone https://github.com/joedefen/ffmpeg-vaapi-docker.git
cd ffmpeg-vaapi-docker
./build.sh    # or: docker build -t joedefen/ffmpeg-vaapi-docker:latest .
./test.sh
./push.sh
```

### Pinning and refreshing the base image

The `FROM` line pins `ubuntu:26.04` to a digest, so base layers change only when the file changes. Package names are not pinned: `ffmpeg` and the drivers follow the archive, which is how security updates arrive.

Nothing refreshes the digest automatically. Do it monthly, or on an Ubuntu point release:

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

If step 2 changes nothing, the pin is current. If it changes, commit the new digest alone.

### Testing a local build

[`test.sh`](test.sh) runs three passes against an image already on the machine: a synthetic 1080p null-source encode, the [Basic Usage](#basic-usage) command against a real file in a temp directory (output must be non-empty and the expected codec), and a compatibility pass over the legacy rmbloat command form and the explicit `--entrypoint` form used since 1.0.5. Three variables:

| Variable | Default | Effect |
| --- | --- | --- |
| `IMAGE_NAME` | `joedefen/ffmpeg-vaapi-docker:latest` | Image under test. |
| `RENDER_DEV` | first `/dev/dri/renderD*` | Render node. Set it on multi-GPU hosts; node numbering does not follow GPU order. |
| `DURATION` | `10` | Seconds of 1080p null-source encode. |

The encoder follows `vainfo`: `hevc_vaapi` when the GPU reports a HEVC encoding entrypoint, else `h264_vaapi` with a warning that HEVC is unavailable on that hardware.

```bash
./test.sh
IMAGE_NAME=ffmpeg-vaapi-docker:labels DURATION=1 ./test.sh
RENDER_DEV=/dev/dri/renderD129 ./test.sh
```

### Publishing

[`push.sh`](push.sh) publishes two tags: an immutable `YYYY.MM.DD.HH.MM-commit` tag — UTC build time plus the 7-character sha, e.g. `2026.11.17.02.40-48f6395` — and a moving tag (`TAG`, default `latest`; `VERSION` overrides the immutable name). It refuses to run unless `git status` is empty — modified, staged and untracked files all count, since the tag and the `org.opencontainers.image.version` label claim to describe that commit; only git-ignored paths such as `tmp/` may exist. It then builds through [`build.sh`](build.sh), runs [`test.sh`](test.sh), and pushes the immutable tag first, so a failure cannot leave `latest` on an untested image. Both scripts honour `IMAGE` and `TAG`.

The image carries `/licenses/LICENSE` and `/licenses/NOTICE` — the GPL source pointer for the FFmpeg binaries, the non-free terms for the Intel driver — so a pulled copy states its own terms. Package copyrights stay where dpkg puts them, under `/usr/share/doc/<package>/copyright`.

#### Publishing with an SBOM and provenance

`push.sh` uses plain `docker build`/`docker push`, so it attaches no attestations. To get them, build and push with buildx:

```bash
docker buildx build \
    --sbom=true --provenance=true \
    --platform linux/amd64 \
    --push \
    -t joedefen/ffmpeg-vaapi-docker:latest .
```

The tag then becomes an OCI index: the image manifest plus an SPDX-2.3 document (298 packages on the current base) and SLSA provenance v1. Inspect with:

```bash
docker buildx imagetools inspect joedefen/ffmpeg-vaapi-docker:latest
```

`attestation-manifest` entries appear beside the `linux/amd64` image entry. Verified with buildx v0.37 against a throwaway local registry.

## Troubleshooting

### Permission Denied Errors

For permission errors on `/dev/dri/`:

```bash
sudo usermod -aG video,render "$USER"
```

Group membership is read at login, so log out and back in — or apply it to a single command:

```bash
sg render -c 'vainfo'
```

If the container still cannot open the device, pass the host render GID: `--group-add "$(getent group render | cut -d: -f3)"`.

Two problems share this wording:

| Message mentions | Cause | Fix |
|---|---|---|
| `/dev/dri/renderD128`, `cannot open device` | group/GID access to the GPU | the steps above |
| `Error opening output <file>: Permission denied` | no `-w` and a relative output path, so FFmpeg writes to `/` | pass `-w`, or an absolute path inside a mounted volume (see [Basic Usage](#basic-usage)) |

The second is not a VA-API problem; the encode never starts.

### No Hardware Acceleration

Run `vainfo` — see [VA-API driver selection](#va-api-driver-selection-libva_driver_name); no profiles usually means the wrong driver.

### Multiple GPUs

With more than one GPU, name the render device:

```bash
ls /dev/dri/

docker run --rm \
    --device=/dev/dri:/dev/dri \
    joedefen/ffmpeg-vaapi-docker:latest \
    -vaapi_device /dev/dri/renderD129 \
    ...
```

## License

The repository's own files are MIT licensed — see [LICENSE](LICENSE).

The container image also redistributes third-party software, including the non-free Intel media driver and a GPL-enabled FFmpeg build. The MIT license does not cover those components; see [NOTICE](NOTICE) for the component list and the GPL source-availability statement, and `/usr/share/doc/<package>/copyright` inside the image for authoritative texts.

## Related Projects

- [FFmpeg](https://ffmpeg.org/)
- [libva](https://github.com/intel/libva)
- [intel-media-driver](https://github.com/intel/media-driver)
- [rmbloat](https://github.com/joedefen/rmbloat)

## Author

[joedefen](https://github.com/joedefen)

---

## Appendix

### Platform: amd64 only

The image targets `linux/amd64` exclusively: `intel-media-va-driver-non-free`, the iHD driver that makes Quick Sync work, is published for `amd64` and no other architecture.

[`build.sh`](build.sh) and the [`Dockerfile`](Dockerfile) refuse anything else, rather than failing inside `apt-get` with "Unable to locate package". On an arm64 host:

```text
$ uname -m
aarch64
$ ./build.sh
ERROR: this image targets linux/amd64 only; requested platform is 'linux/arm64'.
       'intel-media-va-driver-non-free' is not published for arm64.
       On an x86-64 host, omit --platform. To build under emulation anyway,
       pass --platform linux/amd64 deliberately.
```

A plain `docker build` is guarded too. Cross-building `--platform linux/arm64` from x86-64 without binfmt fails one step earlier with `exec /bin/sh: exec format error`, because the guard itself cannot run; install it with `docker run --privileged --rm tonistiigi/binfmt --install arm64`.

Under emulation the build works, but there is no VA-API device to pass through, so the result is a slow CPU-only ffmpeg:

```bash
docker build --platform linux/amd64 -t ffmpeg-vaapi-docker:latest .
```

### Podman (best effort)

Podman is untested: what follows is reasoned, not verified.

An ordinary Docker image, so it should run. Under rootless Podman the container's uid 1000 maps to a subordinate uid, and supplementary groups such as `render` are not inherited unless you ask:

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

- `--group-add keep-groups` (Podman 3.4+, cgroup v2) passes your supplementary groups in, which is what grants render-node access.
- `:z` relabels the bind mount for SELinux; harmless where SELinux is absent.
- `-w /work` is needed: the image defines no working directory.
- [`test.sh`](test.sh) and the helpers invoke `docker` directly and will not work.

### Codec Support

Two floors apply:

- **Driver floor.** iHD starts at Gen8 / Broadwell (2014). Older Intel graphics need the legacy i965 driver, which is not installed, so pre-Gen8 chips do not work at all. On AMD, Mesa's radeonsi covers GCN and newer.
- **Codec floor.** What the silicon encodes varies by generation, independent of the driver.

Approximate, from vendor documentation (not measured on every generation here):

| Encoder | Intel (iHD) | AMD (radeonsi / Mesa) |
| --- | --- | --- |
| H.264 (AVC) | Gen8 / Broadwell (2014)+ | GCN-era (VCE) and newer |
| HEVC 8-bit | Skylake / Gen9 (2015)+ | VCN 1.0 / Vega (2017)+ |
| HEVC 10-bit | Kaby Lake / Gen9.5 (2017)+ | VCN 1.0+, per SKU |
| VP9 | Kaby Lake (2017)+, 8-bit, encode support is spotty | decode only — no VP9 encoder |
| AV1 | decode from Tiger Lake (Gen12); **encode only on Arc/DG2 and Meteor Lake+** — 11th gen is decode only | decode from RDNA 2; encode from RDNA 3 |

The rows people get wrong: 11th-gen Intel has no AV1 *encoder*, and Intel VP9 encoding starts at Kaby Lake, not 9th gen.

`vainfo` inside the container is ground truth for your machine: `VAProfile*` next to `VAEntrypointEnc*`, where only `Enc` means encode.

### Performance Notes

Hardware acceleration typically gives 3-5x the speed of `libx264`/`libx265`, lower CPU use and power draw, and real-time encoding at high resolution. Quality at equal bitrate is slightly below software encoders, and good enough for most material.

### VA-API driver selection (`LIBVA_DRIVER_NAME`)

The image does not set `LIBVA_DRIVER_NAME`, so libva auto-detects: `iHD` on Intel, `radeonsi` on AMD. Auto-detection can pick wrong on hybrid or multi-GPU systems, or when another Intel driver is present. Override it:

```bash
docker run --rm -e LIBVA_DRIVER_NAME=iHD \
    --device=/dev/dri:/dev/dri \
    --group-add "$(getent group render | cut -d: -f3)" \
    --entrypoint vainfo \
    joedefen/ffmpeg-vaapi-docker:latest
```

`LIBVA_DRIVER_NAME=radeonsi` on AMD. If `vainfo` reports no profiles, the driver choice is the usual culprit.

### Bitrate and quality control (`-qp`, `-rc_mode`)

VA-API encoders default to constant QP. `-qp` takes 0–51 (lower is better; 20–25 is a reasonable start) and maps straight to the encoder's QP, so it does not mean the same quality across codecs. For bitrate targeting, pick a rate-control mode:

```bash
# Constant quality (default behaviour)
-c:v hevc_vaapi -rc_mode CQP -qp 24

# Variable bitrate with a target
-c:v hevc_vaapi -rc_mode VBR -b:v 6M -maxrate 8M

# Constant bitrate
-c:v hevc_vaapi -rc_mode CBR -b:v 6M
```

Not every mode exists for every codec and GPU; `ffmpeg -h encoder=hevc_vaapi` shows what this build supports.

### Why `format=nv12,hwupload`

VA-API encoders only accept GPU surfaces in NV12 (8-bit) or P010 (10-bit). When decoding in software, frames live in system memory, so `format=nv12` converts them and `hwupload` moves them to the GPU. With hardware decode (`-hwaccel_output_format vaapi`) frames already live on the GPU and the upload filter is unnecessary.

### Proving it is really accelerated

- Add `-v verbose` and look for the VA-API device FFmpeg opens.
- CPU usage should stay far below software `libx264`/`libx265` for the same input; compare with `docker stats` or `time`.
- `-benchmark` reports throughput; supported hardware should encode 1080p HEVC well above real time.

### Compatibility with older rmbloat releases

[rmbloat](https://github.com/joedefen/rmbloat) is the pipeline this image was built for. Releases up to 1.0.4 passed the low-priority wrapper where the command belongs:

```text
docker run ... IMAGE ionice -c3 nice -n20 -y -progress pipe:2 ... -i in.mkv ...
```

With `ENTRYPOINT ["ffmpeg"]` ffmpeg parsed `-c3` as its own option and exited with `Unrecognized option 'c3'`; with no entry point the wrapper had no ffmpeg to run. The entry point is a small shim:

- the exact legacy prefix `ionice -c3 nice -n20` gets `ffmpeg` inserted after it, so rmbloat <= 1.0.4 works unchanged
- anything starting with an ffmpeg option, or naming its program explicitly, goes straight to `ffmpeg`

rmbloat 1.0.5 and later choose the program with `--entrypoint`, bypassing the shim; `--entrypoint vainfo` and `--entrypoint ffprobe` behave as before.

Only that exact four-word prefix is translated; no arbitrary command is executed. The shim can go when 1.0.4 is out of use.
