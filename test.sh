#!/bin/bash
set -x
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
