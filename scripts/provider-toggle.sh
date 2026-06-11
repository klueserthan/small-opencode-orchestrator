#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/opencode.jsonc"
AGENTS_GLOB="$ROOT_DIR/agents/*.md"

usage() {
  cat <<'EOF'
Usage:
  scripts/provider-toggle.sh status
  scripts/provider-toggle.sh dry-run <opencode-go|ollama-cloud>
  scripts/provider-toggle.sh apply <opencode-go|ollama-cloud>
EOF
}

require_target() {
  local target="${1:-}"
  if [[ "$target" != "opencode-go" && "$target" != "ollama-cloud" ]]; then
    echo "Error: target must be 'opencode-go' or 'ollama-cloud'." >&2
    usage >&2
    exit 1
  fi
}

show_status() {
  local opencode_count ollama_count openai_count

  opencode_count="$(rg -n -g '*.md' -g '*.jsonc' '(^\s*model:\s*|"model"\s*:\s*")opencode-go/' "$ROOT_DIR" | wc -l | tr -d ' ')"
  ollama_count="$(rg -n -g '*.md' -g '*.jsonc' '(^\s*model:\s*|"model"\s*:\s*")ollama-cloud/' "$ROOT_DIR" | wc -l | tr -d ' ')"
  openai_count="$(rg -n -g '*.md' -g '*.jsonc' '(^\s*model:\s*|"model"\s*:\s*")openai/' "$ROOT_DIR" | wc -l | tr -d ' ')"

  echo "Model provider status (model lines only):"
  echo "  opencode-go:  $opencode_count"
  echo "  ollama-cloud: $ollama_count"
  echo "  openai:       $openai_count"
}

show_changes() {
  local from_provider="$1"
  local to_provider="$2"

  rg -n -g '*.md' -g '*.jsonc' "(^\s*model:\s*|\"model\"\s*:\s*\").*${from_provider}/" "$ROOT_DIR" || true

  if ! rg -q -g '*.md' -g '*.jsonc' "(^\s*model:\s*|\"model\"\s*:\s*\").*${from_provider}/" "$ROOT_DIR"; then
    echo "No model lines found using ${from_provider}/."
    return 1
  fi

  echo
  echo "Planned replacement: ${from_provider}/ -> ${to_provider}/ (model lines only)"
}

replace_in_file() {
  local file="$1"
  local from_provider="$2"
  local to_provider="$3"

  perl -0pi -e "s/(^\s*model:\s*)\Q${from_provider}\E\//\1${to_provider}\//mg; s/(\"model\"\s*:\s*\")\Q${from_provider}\E\//\1${to_provider}\//mg" "$file"
}

apply_changes() {
  local target="$1"
  local from_provider
  local backup_dir
  local changed=0

  if [[ "$target" == "opencode-go" ]]; then
    from_provider="ollama-cloud"
  else
    from_provider="opencode-go"
  fi

  if ! rg -q -g '*.md' -g '*.jsonc' "(^\s*model:\s*|\"model\"\s*:\s*\").*${from_provider}/" "$ROOT_DIR"; then
    echo "No model lines found using ${from_provider}/. Nothing to apply."
    exit 1
  fi

  backup_dir="$ROOT_DIR/.provider-toggle-backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir/agents"
  cp "$CONFIG_FILE" "$backup_dir/opencode.jsonc"
  cp $AGENTS_GLOB "$backup_dir/agents/"

  replace_in_file "$CONFIG_FILE" "$from_provider" "$target"

  for agent_file in $AGENTS_GLOB; do
    replace_in_file "$agent_file" "$from_provider" "$target"
  done

  changed="$(git -C "$ROOT_DIR" diff -- "$CONFIG_FILE" "$ROOT_DIR/agents" | wc -l | tr -d ' ')"
  if [[ "$changed" == "0" ]]; then
    echo "No file content changed after apply."
    exit 1
  fi

  echo "Applied provider switch: ${from_provider} -> ${target}"
  echo "Backups saved to: $backup_dir"
  show_status
}

main() {
  local command="${1:-}"
  local target="${2:-}"
  local from_provider

  case "$command" in
    status)
      show_status
      ;;
    dry-run)
      require_target "$target"
      if [[ "$target" == "opencode-go" ]]; then
        from_provider="ollama-cloud"
      else
        from_provider="opencode-go"
      fi
      show_changes "$from_provider" "$target"
      ;;
    apply)
      require_target "$target"
      apply_changes "$target"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"