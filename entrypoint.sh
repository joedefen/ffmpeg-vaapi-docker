#!/bin/sh
# Entry point for the ffmpeg image.
#
# ffmpeg is the program this image exists to run, so an argument list that
# starts with an ffmpeg option (-i, -version, ...) is passed straight to it.
#
# One compatibility case needs a translation instead.  rmbloat releases up to
# 1.0.4 put their low-priority wrapper in the command position and never named
# the binary, producing
#
#     docker run ... IMAGE ionice -c3 nice -n20 -y -progress pipe:2 ...
#
# With ENTRYPOINT ["ffmpeg"] the wrapper words became ffmpeg's own arguments,
# which failed with "Unrecognized option 'c3'" (exit 8); with no entry point at
# all the wrapper had no ffmpeg to run.  Supplying the missing word keeps those
# releases working.
#
# rmbloat 1.0.5 and later select the program with `--entrypoint` themselves and
# never reach this branch.  The match is deliberately limited to the exact
# legacy prefix: this is a compatibility shim, not a general command runner.
set -eu

if [ "${1:-}" = ionice ] &&
   [ "${2:-}" = -c3 ] &&
   [ "${3:-}" = nice ] &&
   [ "${4:-}" = -n20 ]; then
    shift 4
    exec ionice -c3 nice -n20 ffmpeg "$@"
fi

exec ffmpeg "$@"
