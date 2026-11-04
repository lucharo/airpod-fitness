#!/bin/zsh
# Run JavaScript in the PAGE world of the first Brave tab whose URL contains $1 and print
# its (string) result. Apple Events JS runs in an isolated world where React's value setters
# throw "Illegal invocation", so inject a <script> and read the result from a data attribute.
# Usage: brave-page-js.sh <url-substring> <js-file>   (the file is an expression, e.g. an IIFE)
here="${0:A:h}"
body="$(cat "$2")"
wrapper="$(mktemp -t brave-page-js).js"
python3 - "$body" > "$wrapper" <<'PY'
import json, sys
code = sys.argv[1]
inner = "try { document.documentElement.dataset.agentResult = String(" + code + "); } catch (e) { document.documentElement.dataset.agentResult = 'ERR ' + e.message; }"
print("(() => { delete document.documentElement.dataset.agentResult; const s = document.createElement('script'); s.textContent = " + json.dumps(inner) + "; document.documentElement.appendChild(s); s.remove(); return document.documentElement.dataset.agentResult; })()")
PY
"$here/brave-js.sh" "$1" "$wrapper"
rm -f "$wrapper"
