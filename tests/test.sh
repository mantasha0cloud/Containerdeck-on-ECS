#!/bin/bash
# Pre-build smoke tests for ContainerDeck static site
set -e

echo "Running ContainerDeck source tests..."

FILES=("index.html" "style.css" "script.js" "Dockerfile" "nginx.conf")

for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: Missing required file -> $f"
    exit 1
  else
    echo "PASS: Found $f"
  fi
done

if ! grep -q "<html" index.html || ! grep -q "</html>" index.html; then
  echo "FAIL: index.html does not look like valid HTML"
  exit 1
else
  echo "PASS: index.html structure looks valid"
fi

if ! grep -q "EXPOSE 80" Dockerfile; then
  echo "FAIL: Dockerfile does not expose port 80"
  exit 1
else
  echo "PASS: Dockerfile exposes port 80"
fi

echo "All source tests passed."
