#!/usr/bin/env bash
# Switchcraft Theme Monitor
# Watches GNOME color-scheme and runs user-defined commands from commands.json

set -euo pipefail

# Configuration paths
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/switchcraft"
COMMANDS_FILE="$CONFIG_DIR/commands.json"
CONSTANTS_FILE="$CONFIG_DIR/constants.json"

# Load constants from constants.json and export as environment variables
strip_wrapper_quotes() {
    local input="$1"

    if [[ ${#input} -ge 2 ]]; then
        local first_char="${input:0:1}"
        local last_char="${input: -1}"

        if [[ "$first_char" == "'" && "$last_char" == "'" ]]; then
            input="${input:1:-1}"
        elif [[ "$first_char" == '"' && "$last_char" == '"' ]]; then
            input="${input:1:-1}"
        fi
    fi

    printf '%s\n' "$input"
}

expand_shell_value() {
    set +u
    local input="$1"
    local expanded
    expanded=$(eval "printf '%s' \"$input\"" 2>/dev/null) || expanded="$input"
    set -u
    printf '%s\n' "$expanded"
}

load_constants() {
  if [[ ! -f "$CONSTANTS_FILE" ]]; then
    return
  fi
  
  # Parse JSON and export each constant
  while IFS='=' read -r key value; do
    if [[ -n "$key" && -n "$value" ]]; then
      local sanitized_value
      sanitized_value=$(strip_wrapper_quotes "$value")
      local expanded_value
      expanded_value=$(expand_shell_value "$sanitized_value")
      export "$key=$expanded_value"
    fi
  done < <(jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$CONSTANTS_FILE" 2>/dev/null || true)
}

# Execute commands for a specific theme (light or dark)
execute_commands() {
  local theme=$1
  
  if [[ ! -f "$COMMANDS_FILE" ]]; then
    return
  fi
  
  # Load constants for substitution
  load_constants
  
  # Parse commands.json and execute enabled commands for the theme
  jq -r --arg theme "$theme" '
    .[$theme] // [] | 
    .[] | 
    select(.enabled == true) | 
    .command
  ' "$COMMANDS_FILE" 2>/dev/null | while IFS= read -r command; do
    if [[ -n "$command" ]]; then
      # Execute command in a subshell with full shell support
      eval "$command" &
    fi
  done
}

# Monitor theme changes
monitor_theme() {
  # Get initial theme and execute commands once
  local current_scheme
  current_scheme=$(gsettings get org.gnome.desktop.interface color-scheme)
  
  if [[ "$current_scheme" == "'prefer-dark'" ]]; then
    execute_commands "dark"
  else
    execute_commands "light"
  fi
  
  # Monitor for changes
  gsettings monitor org.gnome.desktop.interface color-scheme | while IFS= read -r line; do
    # Extract new scheme from "color-scheme: 'prefer-dark'" format
    local new_scheme="${line#*: }"
    
    if [[ "$new_scheme" == "'prefer-dark'" ]]; then
      execute_commands "dark"
    else
      execute_commands "light"
    fi
  done
}

# Main entry point
main() {
  # Ensure config directory exists
  mkdir -p "$CONFIG_DIR"
  
  # Start monitoring
  monitor_theme
}

main "$@"
