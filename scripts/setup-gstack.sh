#!/bin/sh
# Build gstack browse binary (one-time setup)
# Requires: bun (https://bun.sh)

GSTACK_DIR=".claude/skills/gstack"

if [ ! -d "$GSTACK_DIR" ]; then
  echo "Error: gstack not found at $GSTACK_DIR"
  exit 1
fi

# Check bun
if ! command -v bun > /dev/null 2>&1; then
  echo "bun not found. Installing..."
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
fi

# Install gstack dependencies
echo "Installing gstack dependencies..."
cd "$GSTACK_DIR" && bun install

# Build browse binary
if [ -d "browse/src" ]; then
  echo "Building browse binary..."
  cd browse && sh scripts/build-node-server.sh 2>/dev/null || bun build src/cli.ts --outdir dist --target node
  cd ..
fi

echo "✅ gstack setup complete"
