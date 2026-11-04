#!/bin/zsh
# Run JavaScript in the first Brave tab whose URL contains $1, on the machine this runs on.
# Usage: brave-js.sh <url-substring> <js-file>
# Needs Brave: View > Developer > Allow JavaScript from Apple Events.
match="$1"
js="$(cat "$2")"
osascript - "$match" "$js" <<'OSA'
on run argv
  set m to item 1 of argv
  set code to item 2 of argv
  tell application "Brave Browser"
    repeat with w in windows
      repeat with t in tabs of w
        if URL of t contains m then
          return execute t javascript code
        end if
      end repeat
    end repeat
  end tell
  return "NO TAB MATCHING " & m
end run
OSA
