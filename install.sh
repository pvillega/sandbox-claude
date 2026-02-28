#!/usr/bin/env bash
# install.sh — Install wrapper scripts for all bin/sandbox* commands into a directory in your PATH
set -euo pipefail

DEST="${1:-${HOME}/.local/bin}"
mkdir -p "$DEST"

SCRIPT_DIR="$(cd "$(dirname "$0")/bin" && pwd)"

# Clean up old symlinks from previous installs
for script in "${SCRIPT_DIR}"/sandbox*; do
  name="$(basename "$script")"
  target="${DEST}/${name}"
  if [[ -L "$target" ]]; then
    rm "$target"
  fi
done

echo "Installing sandbox commands to ${DEST}..."
echo ""

for script in "${SCRIPT_DIR}"/sandbox*; do
  name="$(basename "$script")"
  chmod +x "$script"
  cat > "${DEST}/${name}" <<EOF
#!/usr/bin/env bash
exec "${script}" "\$@"
EOF
  chmod +x "${DEST}/${name}"
  echo "  ${name} → ${DEST}/${name}"
done

echo ""

# Check if DEST is in PATH
if [[ ":$PATH:" != *":${DEST}:"* ]]; then
  echo "WARNING: ${DEST} is not in your PATH."
  echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
  echo ""
  echo "  export PATH=\"\$PATH:${DEST}\""
  echo ""
fi

echo "Done. Run 'sandbox-setup' to initialise the infrastructure."
