#!/bin/sh
# Setup git hooks for the project
# Run after git clone: sh scripts/setup-hooks.sh

HOOKS_DIR=".git/hooks"

if [ ! -d ".git" ]; then
  echo "Error: Not a git repository. Run 'git init' first."
  exit 1
fi

mkdir -p "$HOOKS_DIR"

# pre-push: Block direct push to main
cat > "$HOOKS_DIR/pre-push" << 'HOOK'
#!/bin/sh
protected_branch="main"
current_branch=$(git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,')

if [ "$current_branch" = "$protected_branch" ]; then
    echo ""
    echo "🚫 Direct push to '$protected_branch' is blocked."
    echo "   Use a PR from 'dev' branch instead."
    echo ""
    echo "   Workflow: feat/* → dev (PR) → main (PR)"
    echo ""
    echo "   To bypass (emergency only): git push --no-verify"
    echo ""
    exit 1
fi

exit 0
HOOK

chmod +x "$HOOKS_DIR/pre-push"

echo "✅ Git hooks installed:"
echo "   - pre-push: blocks direct push to main"
