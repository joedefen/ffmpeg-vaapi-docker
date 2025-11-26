#!/bin/bash
set -e

(set -x; docker build -t joedefen/ffmpeg-vaapi-docker:latest .)
(set -x ; docker push joedefen/ffmpeg-vaapi-docker:latest)

echo "Successfully pushed joedefen/ffmpeg-vaapi-docker:latest"
