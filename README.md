# zsh-explain-autofix 🛠️✨

**Alt+E error diagnostic & auto-fix injector for zsh** 🚨💡

Captures a failed command's stderr + exit code, generates an instant inline explanation, and injects a suggested fix into your command buffer — all with a single keypress. Never auto-executes; safe by default.

---

## Features 🌟

- **`Alt+E`** after any failed command → explanation + suggested fix in your buffer ⌨️📝
- **Local pattern rules** for git 🐙, pacman 📦, apt 📦, docker 🐳, ssh 🔐, systemctl ⚙️, cargo 🦀, npm 📦 — fast, no network
- **Optional LLM fallback** via OpenAI-compatible API for unmatched errors 🤖🌐
- **User-custom rules** via `ZEA_USER_RULES` config file 🎨
- **Fix confirmation prompt** before injecting — opt out with `ZEA_CONFIRM=0` ✅❌
- **Stderr capture** via `preexec`/`precmd` hooks 🪝
- **Buffer injection** — fix appears in your command line, ready to edit or execute 💉✏️
- **Omarchy bar integration** — shows "⚠ last command failed" indicator 📊

---

## Install 📦

### One-liner (curl)

```bash
curl -fsSL https://raw.githubusercontent.com/cybercoretech/zsh-explain-autofix/main/install.sh | bash
```

### Manual

Add to your `~/.zshrc`:

```zsh
source /home/raven/Devspace/Cybercore/tooling/zsh-explain-autofix/explain-autofix.zsh
```

Then press **`Alt+E`** after a command fails. 🎯

---

## Configuration ⚙️

Set these in `~/.zshrc` **before** sourcing the plugin:

| Variable | Default | Description |
|----------|---------|-------------|
| `ZEA_STATE_DIR` | `${XDG_CACHE_HOME:-$HOME/.cache}/zsh-explain-autofix` | State file directory 📁 |
| `ZEA_LLM_API_KEY` | _(unset)_ | OpenAI-compatible API key (optional LLM fallback) 🔑 |
| `ZEA_LLM_BASE_URL` | `https://api.openai.com/v1` | LLM base URL 🌐 |
| `ZEA_LLM_MODEL` | `gpt-4o-mini` | LLM model 🧠 |
| `ZEA_AUTO_CLEAR` | `1` | Clear failure state after `Alt+E` 🧹 |
| `ZEA_KEY_BIND` | `'\eE'` (Alt+E) | Custom key sequence ⌨️ |
| `ZEA_CONFIRM` | `1` | Ask before injecting fix ✅❌ |
| `ZEA_USER_RULES` | _(unset)_ | Path to your custom rules file 📜 |
| `ZEA_BAR_INDICATOR` | _(unset)_ | Path to Omarchy bar indicator script 📊 |

### Example `.zshrc` snippet

```zsh
source /home/raven/Devspace/Cybercore/tooling/zsh-explain-autofix/explain-autofix.zsh

# Optional: enable LLM backend for unmatched errors
export ZEA_LLM_API_KEY="sk-..."
export ZEA_LLM_MODEL="gpt-4o-mini"

# Optional: skip confirmation, inject fix directly
export ZEA_CONFIRM=0

# Optional: custom key binding
export ZEA_KEY_BIND='^[e'
```

---

## Usage 📖

```zsh
$ git pushe
fatal: 'pushe' is not a git command. See 'git --help'.

$                                    # press Alt+E ⌨️
%YELLOW%Command Failed (exit 128)%RESET%
Command: git pushe
Stderr: fatal: 'pushe' is not a git command...
Explanation: That git subcommand doesn't exist. Did you mean 'push'?
Suggested fix: git push
Apply fix? (y/n): y                  # confirmation prompt ✅
$ git push                            # fix injected into buffer 💉
# press Enter to run, or edit first ▶️
```

---

## Custom Rules 🎨

Create a rules file and set `ZEA_USER_RULES` to its path. The file should define a function `_zea_user_rule_match()` that takes 5 name-reference args:

```zsh
_zea_user_rule_match() {
    local -n _cmd=$1 _code=$2 _stderr=$3 _expl=$4 _fix=$5
    _expl=""
    _fix=""
    if [[ "$_cmd" == mytool* ]] && [[ "$_stderr" == *"auth expired"* ]]; then
        _expl="Your mytool auth token expired."
        _fix="mytool login --refresh"
        return 0
    fi
    return 1
}
```

---

## Omarchy Bar Integration 📊

Set `ZEA_BAR_INDICATOR` to a script path. The plugin will write a failure flag file that your bar widget can read to show a "⚠" indicator when the last command failed.

Example bar widget check:
```zsh
if [[ -f "${XDG_CACHE_HOME:-$HOME/.cache}/zsh-explain-autofix/last-failure.json" ]]; then
    echo "⚠"
fi
```

---

## License 📄

MIT

---

<p align="center">
  Made with ❤️ for zsh power users
</p>
