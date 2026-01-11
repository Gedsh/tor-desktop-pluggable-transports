#!/usr/bin/env bash
set -e

VERSION=$(cat version.txt)
REPO_ROOT=$(pwd)
STATE="$REPO_ROOT/state"
STATE_FILE="$STATE/builded.json"
DIST="$REPO_ROOT/dist"
CACHE="$REPO_ROOT/cache"

mkdir -p "$STATE" "$DIST" "$CACHE"

if [ ! -f "$STATE_FILE" ]; then
  echo "{}" > "$STATE_FILE"
fi

# Define targets clearly
TARGETS=(
  "linux   amd64"
  "windows amd64"
  "darwin  amd64"
  "darwin  arm64"
)

# Iterate over each repo
jq -c '.[]' repos.json | while read -r row; do
  name=$(echo "$row" | jq -r '.name')
  url=$(echo "$row" | jq -r '.url')
  branch=$(echo "$row" | jq -r '.branch')
  main=$(echo "$row" | jq -r '.main')

  echo "=== Processing $name ==="

  # Clean old repo folder
  rm -rf "$name"
  git clone --single-branch --branch "$branch" "$url" "$name"

  # Get commit hash
  commit=$(git -C "$name" rev-parse HEAD)
  prev=$(jq -r --arg n "$name" '.[$n] // empty' "$STATE_FILE")

  # Reuse binaries if commit matches and cache exists
  if [ "$commit" = "$prev" ] && ls "$CACHE"/${name}-* 1> /dev/null 2>&1; then
    echo "Reusing cached binaries for $name"
    cp "$CACHE"/${name}-* "$DIST"/
    continue
  fi

  echo "Building $name"

  # Build each target
  for target in "${TARGETS[@]}"; do
    read -r GOOS GOARCH <<< "$target"

    EXT=""
    [ "$GOOS" = "windows" ] && EXT=".exe"

    echo "  Building for $GOOS/$GOARCH"

    # Build binary
    TARGET_DIR="$name/$main"
    if [ ! -d "$TARGET_DIR" ]; then
      echo "Error: $TARGET_DIR does not exist"
      exit 1
    fi

    pushd "$TARGET_DIR" > /dev/null

    env GOOS=$GOOS GOARCH=$GOARCH CGO_ENABLED=0 \
      go build -trimpath -ldflags="-s -w" \
      -o "$DIST/${name}-${GOOS}-${GOARCH}${EXT}"

    popd > /dev/null
  done

  # Update cache: remove old cached binaries first
  rm -f "$CACHE/${name}-"* 2>/dev/null
  cp "$DIST"/${name}-* "$CACHE"/

  # Update build state
  jq --arg n "$name" --arg c "$commit" \
    '.[$n]=$c' "$STATE_FILE" > tmp && mv tmp "$STATE_FILE"

done

