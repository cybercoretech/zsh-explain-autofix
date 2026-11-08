#!/usr/bin/env zsh
#
# zsh-explain-autofix — Alt+E error diagnostic & auto-fix injector
#
# Captures the last failed command's stderr + exit code, generates an
# instant inline explanation, and (optionally) injects a suggested fix
# into the zle buffer with a single keypress. Never auto-executes — safe
# by default.
#
# Source this file from ~/.zshrc, then press Alt+E after a failed command.
#
# Configuration (all optional, set in ~/.zshrc before sourcing):
#   ZEA_STATE_DIR      Where state files are kept
#                        (default: ${XDG_CACHE_HOME:-$HOME/.cache}/zsh-explain-autofix)
#   ZEA_LLM_API_KEY    OpenAI-compatible API key (optional LLM fallback)
#   ZEA_LLM_BASE_URL   LLM base URL (default: https://api.openai.com/v1)
#   ZEA_LLM_MODEL      LLM model (default: gpt-4o-mini)
#   ZEA_AUTO_CLEAR     Clear failure state after Alt+E (default: 1)
#   ZEA_KEY_BIND       Custom key sequence (default: '\eE' for Alt+E)
#   ZEA_CONFIRM        Ask before injecting fix (default: 1)
#   ZEA_USER_RULES     Path to your custom rules file
#   ZEA_BAR_INDICATOR  Path to zea-bar-indicator script (for Omarchy bar)
#

# ---------------------------------------------------------------------------
# Setup state directory
# ---------------------------------------------------------------------------
ZEA_STATE_DIR="${ZEA_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh-explain-autofix}"
ZEA_STATE_FILE="$ZEA_STATE_DIR/last-failure.json"
ZEA_STDERR_FILE="$ZEA_STATE_DIR/last-stderr.txt"
ZEA_CMD_FILE="$ZEA_STATE_DIR/last-command.txt"

mkdir -p "$ZEA_STATE_DIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# JSON escaping helper (for writing state safely)
# ---------------------------------------------------------------------------
_zea_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    print -rn -- "$s"
}

# ---------------------------------------------------------------------------
# preexec: stash the command about to run and redirect stderr to a file
# ---------------------------------------------------------------------------
_zea_preexec() {
    local cmd="$1"
    # Only capture if we're in an interactive tty (avoid breaking scripts)
    if [[ -t 2 ]]; then
        exec 2>"$ZEA_STDERR_FILE" 2>/dev/null || true
    fi
    print -rn -- "$cmd" > "$ZEA_CMD_FILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# precmd: after command finishes, record failure state if exit != 0
# ---------------------------------------------------------------------------
_zea_precmd() {
    local exit_code=$?

    # Restore stderr to the terminal
    if [[ -t 2 ]]; then
        exec 2>/dev/tty 2>/dev/null || true
    fi

    local cmd stderr
    cmd=$(cat "$ZEA_CMD_FILE" 2>/dev/null || true)
    stderr=$(cat "$ZEA_STDERR_FILE" 2>/dev/null || true)

    # Clear stale state on success
    if [[ $exit_code -eq 0 || -z "$cmd" ]]; then
        rm -f "$ZEA_STATE_FILE" 2>/dev/null || true
        return 0
    fi

    # Write failure state as JSON
    cat > "$ZEA_STATE_FILE" 2>/dev/null <<EOF
{"command":"$(_zea_json_escape "$cmd")","exit_code":$exit_code,"stderr":"$(_zea_json_escape "$stderr")","timestamp":$(date +%s),"cwd":"$(_zea_json_escape "$PWD")"}
EOF
}

# ---------------------------------------------------------------------------
# Hook registration
# ---------------------------------------------------------------------------
if [[ -z "${_ZEA_HOOKS_INSTALLED:-}" ]]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook preexec _zea_preexec
    add-zsh-hook precmd _zea_precmd
    _ZEA_HOOKS_INSTALLED=1
fi

# ---------------------------------------------------------------------------
# Explanation engine — local pattern rules
# ---------------------------------------------------------------------------
# Sets _ZEA_EXPLANATION and _ZEA_FIX (by name reference)
_zea_rule_match() {
    local -n _cmd=$1 _code=$2 _stderr=$3
    local -n _expl=$4 _fix=$5
    _expl=""
    _fix=""

    local c="$_cmd"
    local e="$_stderr"

    # ---- Git ----
    if [[ "$c" == git* ]]; then
        if [[ "$e" == *"' is not a git command."* ]]; then
            _expl="That git subcommand doesn't exist. Did you mean 'push'?"
            _fix=$(print -rn -- "$c" | sed "s/git [a-z-]* /git push /" 2>/dev/null)
            [[ -z "$_fix" ]] && _fix="git push"
        elif [[ "$e" == *"failed to push"* ]] || [[ "$e" == *"rejected"* ]]; then
            _expl="Your push was rejected — your local branch is likely behind the remote."
            _fix="git pull --rebase && git push"
        elif [[ "$e" == *"not anything"* ]] || [[ "$e" == *"unknown option"* ]]; then
            _expl="Unrecognised git option or argument."
            _fix="git --help"
        elif [[ "$e" == *"authentication failed"* ]]; then
            _expl="Git authentication failed — check your credentials or SSH key."
            _fix="git config --global credential.helper store"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- pacman (Arch) ----
    if [[ "$c" == pacman* ]]; then
        if [[ "$e" == *"conflicting files"* ]]; then
            _expl="A file conflict is blocking the transaction."
            _fix="sudo pacman -S --overwrite '*' <package>"
        elif [[ "$e" == *"database lock"* ]] || [[ "$e" == *"lock"* ]]; then
            _expl="Another pacman process holds the database lock."
            _fix="sudo rm /var/lib/pacman/db.lck && sudo pacman -Syu"
        elif [[ "$e" == *"target not found"* ]]; then
            _expl="Package not found in repositories."
            _fix="pacman -Ss <package-name>"
        elif [[ "$e" == *"invalid or corrupted package"* ]]; then
            _expl="Package cache is corrupted."
            _fix="sudo pacman -Sc && sudo pacman -Syu"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- apt / apt-get ----
    if [[ "$c" == apt* ]] || [[ "$c" == apt-get* ]]; then
        if [[ "$e" == *"Unable to locate package"* ]]; then
            _expl="Package not found in apt repositories."
            _fix="apt search <package-name>"
        elif [[ "$e" == *"could not be obtained"* ]] || [[ "$e" == *"lock"* ]]; then
            _expl="Another apt/dpkg process holds the lock."
            _fix="sudo killall apt apt-get dpkg 2>/dev/null; sudo dpkg --configure -a"
        elif [[ "$e" == *"E: Sub-process"* ]] || [[ "$e" == *"dpkg error"* ]]; then
            _expl="dpkg encountered an error processing packages."
            _fix="sudo dpkg --configure -a && sudo apt install -f"
        elif [[ "$e" == *"repository does not have"* ]]; then
            _expl="Repository signature verification failed."
            _fix="sudo apt-get update"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- docker ----
    if [[ "$c" == docker* ]]; then
        if [[ "$e" == *"permission denied"* ]]; then
            _expl="Docker socket requires root or docker group membership."
            _fix="sudo usermod -aG docker $USER && newgrp docker"
        elif [[ "$e" == *"not found"* ]] && [[ "$c" == "docker "* ]]; then
            _expl="Docker daemon may not be running."
            _fix="sudo systemctl start docker"
        elif [[ "$e" == *"image not found"* ]]; then
            _expl="Docker image not found locally or in registry."
            _fix="docker pull <image-name>"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- kubectl ----
    if [[ "$c" == kubectl* ]]; then
        if [[ "$e" == *"connection refused"* ]]; then
            _expl="kubectl cannot reach the API server — check your cluster/context."
            _fix="kubectl config current-context && kubectl cluster-info"
        elif [[ "$e" == *"namespaces not found"* ]] || [[ "$e" == *"namespace \"*\" not found"* ]]; then
            _expl="The specified namespace doesn't exist."
            _fix="kubectl get namespaces"
        elif [[ "$e" == *"the server has asked for the client"* ]]; then
            _expl="kubectl needs authentication — log in to the cluster."
            _fix="kubectl login"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- ssh ----
    if [[ "$c" == ssh* ]]; then
        if [[ "$e" == *"Connection refused"* ]]; then
            _expl="SSH port is closed or host is unreachable."
            _fix="ssh -p <port> <user>@<host>"
        elif [[ "$e" == *"Permission denied (publickey)"* ]]; then
            _expl="SSH key authentication failed."
            _fix="ssh-copy-id <user>@<host>"
        elif [[ "$e" == *"Host key verification failed"* ]]; then
            _expl="Remote host key has changed (possible MITM or reinstalled host)."
            _fix="ssh-keygen -R <host> && ssh <user>@<host>"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- systemctl ----
    if [[ "$c" == systemctl* ]]; then
        if [[ "$e" == *"Unit "* ]] && [[ "$e" == *"not found"* ]]; then
            _expl="That systemd unit doesn't exist."
            _fix="systemctl list-unit-files | grep <service>"
        elif [[ "$e" == *"Failed to connect to bus"* ]]; then
            _expl="systemd bus is not available (container or non-systemd boot)."
            _fix=""
        elif [[ "$e" == *"Operation failed"* ]] || [[ "$e" == *"Failed to start"* ]]; then
            _expl="The systemd unit failed to start. Check the logs."
            _fix="journalctl -u <service> -n 50 --no-pager"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- flatpak ----
    if [[ "$c" == flatpak* ]]; then
        if [[ "$e" == *"not installed"* ]]; then
            _expl="The Flatpak application is not installed."
            _fix="flatpak install flathub <app-id>"
        elif [[ "$e" == *"remote not found"* ]]; then
            _expl="The Flathub remote is not configured."
            _fix="flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- snap ----
    if [[ "$c" == snap* ]]; then
        if [[ "$e" == *"not found"* ]]; then
            _expl="The snap package was not found."
            _fix="snap find <package-name>"
        elif [[ "$e" == *"connection error"* ]]; then
            _expl="Snap store is unreachable — check your network."
            _fix="sudo snap refresh"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- brew ----
    if [[ "$c" == brew* ]]; then
        if [[ "$e" == *"command not found"* ]]; then
            _expl="Homebrew is not installed or not in PATH."
            _fix="/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        elif [[ "$e" == *"update"* ]] || [[ "$e" == *"outdated"* ]]; then
            _expl="Your Homebrew formulae are outdated."
            _fix="brew update && brew upgrade"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- make ----
    if [[ "$c" == make* ]]; then
        if [[ "$e" == *"No targets"* ]] || [[ "$e" == *"no target"* ]]; then
            _expl="No build targets found — check your Makefile."
            _fix="make help"
        elif [[ "$e" == *"missing separator"* ]]; then
            _expl="Makefile has a syntax error (usually spaces instead of tabs)."
            _fix=""
        elif [[ "$e" == *"Error "* ]] && [[ "$e" == *"Stop."* ]]; then
            _expl="The build failed — see the error above for details."
            _fix=""
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- gcc / g++ ----
    if [[ "$c" == gcc* ]] || [[ "$c" == g++* ]]; then
        if [[ "$e" == *"No such file or directory"* ]]; then
            _expl="Source file not found — check the filename and path."
            _fix="ls *.c *.cpp 2>/dev/null"
        elif [[ "$e" == *"undefined reference"* ]]; then
            _expl="Linker error — missing library or object file."
            _fix=""
        elif [[ "$e" == *"expected ';'"* ]] || [[ "$e" == *"expected '"'"]] ]]; then
            _expl="Syntax error in source code — check the line indicated."
            _fix=""
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- cargo ----
    if [[ "$c" == cargo* ]]; then
        if [[ "$e" == *"could not register"* ]] || [[ "$e" == *"lock"* ]]; then
            _expl="Cargo lock contention."
            _fix="rm -rf target/debug/.fslock target/release/.fslock"
        elif [[ "$e" == *"could not find crate"* ]]; then
            _expl="Rust crate not found in Cargo.toml or crates.io."
            _fix="cargo search <crate-name>"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- npm / yarn / pnpm ----
    if [[ "$c" == npm* ]] || [[ "$c" == yarn* ]] || [[ "$c" == pnpm* ]]; then
        if [[ "$e" == *"E404"* ]] || [[ "$e" == *"not found"* ]]; then
            _expl="Package not found in the registry."
            _fix="npm search <package-name>"
        elif [[ "$e" == *"EACCES"* ]] || [[ "$e" == *"permission denied"* ]]; then
            _expl="Permission error — avoid sudo with npm; fix ownership instead."
            _fix="sudo chown -R $USER:$(id -gn) $HOME/.npm $HOME/.config/yarn"
        elif [[ "$e" == *"ERR! code ELIFECYCLE"* ]]; then
            _expl="A package lifecycle script failed."
            _fix="npm install && npm run build"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- pip / pip3 ----
    if [[ "$c" == pip* ]] || [[ "$c" == python3* ]] || [[ "$c" == python* ]]; then
        if [[ "$e" == *"externally managed"* ]]; then
            _expl="Python packages must be installed in a virtual environment."
            _fix="python3 -m venv .venv && source .venv/bin/activate"
        elif [[ "$e" == *"No matching distribution"* ]]; then
            _expl="Package not found on PyPI."
            _fix="pip search <package-name>"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- journalctl ----
    if [[ "$c" == journalctl* ]]; then
        if [[ "$e" == *"No journal files"* ]]; then
            _expl="No journal files found — systemd journal may not be active."
            _fix=""
        elif [[ "$e" == *"Permission denied"* ]]; then
            _expl="Journal access requires root or systemd-journal group."
            _fix="sudo journalctl $*"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- wget / curl ----
    if [[ "$c" == wget* ]] || [[ "$c" == curl* ]]; then
        if [[ "$e" == *"404"* ]] || [[ "$e" == *"Not Found"* ]]; then
            _expl="The requested URL was not found (HTTP 404)."
            _fix=""
        elif [[ "$e" == *"Connection refused"* ]]; then
            _expl="Connection refused — the server may be down or blocking you."
            _fix=""
        elif [[ "$e" == *"SSL"* ]] || [[ "$e" == *"certificate"* ]]; then
            _expl="SSL certificate verification failed."
            _fix="curl -k <url>  (insecure — only for testing)"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- tar ----
    if [[ "$c" == tar* ]]; then
        if [[ "$e" == *"Cannot open"* ]]; then
            _expl="Archive file not found or unreadable."
            _fix="ls -la <archive-file>"
        elif [[ "$e" == *"Unexpected EOF"* ]]; then
            _expl="Archive is truncated or incomplete."
            _fix="Re-download the archive"
        fi
        [[ -n "$_fix" ]] && return 0
    fi

    # ---- User-defined rules (sourced from ZEA_USER_RULES if set) ----
    if [[ -n "${ZEA_USER_RULES:-}" && -r "$ZEA_USER_RULES" ]]; then
        # shellcheck disable=SC1090
        source "$ZEA_USER_RULES"
        if _zea_user_rule_match "$_cmd" "$_code" "$_stderr" _expl _fix 2>/dev/null; then
            [[ -n "$_fix" ]] && return 0
        fi
    fi

    return 1
}

# ---------------------------------------------------------------------------
# Optional LLM backend
# ---------------------------------------------------------------------------
_zea_llm_explain() {
    local cmd="$1" code="$2" stderr="$3"
    local -n _expl=$4 _fix=$5
    _expl=""
    _fix=""

    [[ -z "${ZEA_LLM_API_KEY:-}" ]] && return 1
    [[ -z "$stderr" ]] && return 1

    local base_url="${ZEA_LLM_BASE_URL:-https://api.openai.com/v1}"
    local model="${ZEA_LLM_MODEL:-gpt-4o-mini}"

    local payload
    payload=$(python3 -c "import json,sys; print(json.dumps({'model': sys.argv[1], 'messages': [{'role': 'user', 'content': f'''You are a command-line error explainer. Given a failed shell command, its exit code, and stderr, respond ONLY with valid JSON: {{\"explanation\": \"one sentence\", \"fix\": \"suggested command or empty string\"}}. Command: {sys.argv[2]} Exit code: {sys.argv[3]} Stderr: {sys.argv[4]}'''}], 'temperature': 0.2})" "$model" "$cmd" "$code" "$stderr" 2>/dev/null)

    local response
    response=$(curl -s --max-time 15 -X POST "$base_url/chat/completions" \
        -H "Authorization: Bearer $ZEA_LLM_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null) || return 1

    _expl=$(print -rn -- "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('choices',[{}])[0].get('message',{}).get('content',''))" 2>/dev/null | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('explanation',''))" 2>/dev/null)
    _fix=$(print -rn -- "$response" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('fix',''))" 2>/dev/null)

    [[ -n "$_expl" ]] && return 0
    return 1
}

# ---------------------------------------------------------------------------
# Generate explanation + fix from state
# ---------------------------------------------------------------------------
_zea_generate_explanation() {
    local state="$1"
    local -n _expl=$2 _fix=$3
    _expl=""
    _fix=""

    local command exit_code stderr
    command=$(print -rn -- "$state" | python3 -c "import sys,json; print(json.load(sys.stdin)['command'])" 2>/dev/null)
    exit_code=$(print -rn -- "$state" | python3 -c "import sys,json; print(json.load(sys.stdin)['exit_code'])" 2>/dev/null)
    stderr=$(print -rn -- "$state" | python3 -c "import sys,json; print(json.load(sys.stdin)['stderr'])" 2>/dev/null)

    # Try local rules first (fast, no network)
    if _zea_rule_match command exit_code stderr _expl _fix; then
        return 0
    fi

    # Fallback to LLM if configured
    if _zea_llm_explain "$command" "$exit_code" "$stderr" _expl _fix; then
        return 0
    fi

    # Generic fallback
    _expl="Command exited with code $exit_code. No pattern matched and no LLM backend configured."
    _fix=""
    return 1
}

# ---------------------------------------------------------------------------
# zle widget — Alt+E  (explain + optional fix confirmation + injection)
# ---------------------------------------------------------------------------
_zea_explain_and_fix() {
    # No failure state?
    if [[ ! -f "$ZEA_STATE_FILE" ]]; then
        zle -M "No recent command failure to explain."
        return 1
    fi

    local state
    state=$(cat "$ZEA_STATE_FILE" 2>/dev/null) || {
        zle -M "Could not read failure state."
        return 1
    }

    local command exit_code stderr explanation fix
    command=$(print -rn -- "$state" | python3 -c "import sys,json; print(json.load(sys.stdin)['command'])" 2>/dev/null)
    exit_code=$(print -rn -- "$state" | python3 -c "import sys,json; print(json.load(sys.stdin)['exit_code'])" 2>/dev/null)
    stderr=$(print -rn -- "$state" | python3 -c "import sys,json; print(json.load(sys.stdin)['stderr'])" 2>/dev/null)

    if ! _zea_generate_explanation "$state" explanation fix; then
        zle -M "Could not generate an explanation for this failure."
        return 1
    fi

    # Display explanation above the prompt
    print -z "\n%F{yellow}═══ Command Failed (exit $exit_code) ═══%f"
    print -z "%F{cyan}Command:%f $command"
    print -z "%F{red}Stderr:%f $stderr"
    print -z "%F{green}%BExplanation:%b%f $explanation"

    if [[ -n "$fix" ]]; then
        print -z "%F{magenta}%BSuggested fix:%b%f $fix"

        # Confirmation prompt
        if [[ "${ZEA_CONFIRM:-1}" == "1" ]]; then
            print -n "%F{yellow}Apply fix? (y/n):%f "
            local confirm
            read -k 1 confirm 2>/dev/null || confirm="n"
            print -z ""  # newline after the keypress

            if [[ "$confirm" == [yY] ]]; then
                LBUFFER="$fix"
                zle end-of-line
                zle -M "Fix injected into buffer. Press Enter to run, or edit."
            else
                zle -M "Fix not applied."
            fi
        else
            LBUFFER="$fix"
            zle end-of-line
            zle -M "Fix injected into buffer. Press Enter to run, or edit."
        fi
    else
        zle -M "Explanation shown above. No automatic fix available."
    fi

    # Optionally clear state so Alt+E doesn't re-fire on the same error
    if [[ "${ZEA_AUTO_CLEAR:-1}" == "1" ]]; then
        rm -f "$ZEA_STATE_FILE" 2>/dev/null || true
    fi
}

zle -N _zea_explain_and_fix

# ---------------------------------------------------------------------------
# Keybinding
# ---------------------------------------------------------------------------
_zea_bind_keys() {
    local key="${ZEA_KEY_BIND:-$'\eE'}"
    bindkey "$key" _zea_explain_and_fix 2>/dev/null || true
    bindkey '^[[27;5;69i' _zea_explain_and_fix 2>/dev/null || true   # some terminals
    bindkey '\e[27;5;69i' _zea_explain_and_fix 2>/dev/null || true
}

_zea_bind_keys

# ---------------------------------------------------------------------------
# Helper: detect your terminal's Alt+E sequence
# ---------------------------------------------------------------------------
zea-detect-key() {
    print -z "Press Alt+E now, then Enter. I'll show the escape sequence."
    read -rk seq
    print -z "Detected: ${(qq)seq}"
    print -z "Add to ~/.zshrc:  bindkey '${(qq)seq}' _zea_explain_and_fix"
}
