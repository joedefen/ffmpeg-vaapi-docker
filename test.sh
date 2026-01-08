#!/bin/bash
set -x

# Updated to match your established name
IMAGE_NAME="joedefen/ffmpeg-vaapi-docker:latest"

echo "--- Checking VA-API Capabilities ---"
docker run --rm --device=/dev/dri:/dev/dri --entrypoint vainfo $IMAGE_NAME

echo -e "\n--- Testing HEVC Hardware Encoding ---"
docker run --rm \
    --device=/dev/dri:/dev/dri \
    --ipc=host \
    $IMAGE_NAME \
    -y \
    -init_hw_device vaapi=va:/dev/dri/renderD128 \
    -filter_hw_device va \
    -f lavfi -i nullsrc=s=1920x1080:d=10 \
    -vf 'format=nv12,hwupload' \
    -c:v hevc_vaapi \
    -f null -