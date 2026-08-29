#!/bin/bash
#
# Launches FinderBack.app as a real app (so Accessibility permission is granted
# to "FinderBack" rather than to your terminal), and streams its debug output
# from the unified log. Ctrl-C stops the log stream; use ./kill.sh to stop the app.
#
cd "$(dirname "$0")"
open ./FinderBack.app
echo "launched FinderBack.app — streaming debug output (Ctrl-C to stop watching):"
exec log stream --style compact --level debug --predicate 'subsystem == "com.github.adfd3ewdf3.FinderBack"'
