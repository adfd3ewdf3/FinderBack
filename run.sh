#!/bin/bash
#
# Runs FinderBack in the foreground so you can watch the debug output.
# Ctrl-C to stop.
#
# NOTE: launched this way, macOS attributes Accessibility permission to your
# TERMINAL app, not to FinderBack. If the permission prompt names Terminal /
# iTerm / Ghostty, that is expected — approve that entry. If you'd rather grant
# it to FinderBack itself, use ./run-bundle.sh instead.
#
cd "$(dirname "$0")"
exec ./FinderBack.app/Contents/MacOS/FinderBack "$@"
