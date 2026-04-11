import Foundation

enum ShellIntegrationBootstrap {
    static func script() -> String {
        #"""
# ---- ContainEye OSC 4545 integration (session-scoped) ----
_ce_osc4545_encode() { printf "%s" "$1" | base64 | tr -d '\n'; }
_ce_osc4545_cwd() { printf "\033]4545;SetCwd;%s\a" "$(_ce_osc4545_encode "$PWD")"; }
_ce_osc4545_prompt_begins() { printf "\033]4545;ShellPromptBegins\a"; }
_ce_osc4545_prompt_ends() { printf "\033]4545;ShellPromptEnds\a"; }
_ce_osc4545_command_started() { printf "\033]4545;CommandStarted;%s\a" "$(_ce_osc4545_encode "$1")"; }
_ce_osc4545_command_exited() { printf "\033]4545;CommandExited;%s\a" "$1"; }

if [ -n "$ZSH_VERSION" ]; then
  autoload -Uz add-zsh-hook >/dev/null 2>&1
  _ce_osc4545_precmd() { local ec=$?; _ce_osc4545_cwd; _ce_osc4545_prompt_begins; _ce_osc4545_prompt_ends; _ce_osc4545_command_exited "$ec"; }
  _ce_osc4545_preexec() { _ce_osc4545_command_started "$1"; }
  add-zsh-hook precmd _ce_osc4545_precmd >/dev/null 2>&1
  add-zsh-hook preexec _ce_osc4545_preexec >/dev/null 2>&1
elif [ -n "$BASH_VERSION" ]; then
  _ce_osc4545_preexec_invoke_exec() {
    [ -n "$COMP_LINE" ] && return
    local cmd
    cmd=$(HISTTIMEFORMAT= history 1 | sed 's/^ *[0-9]\+ *//')
    _ce_osc4545_command_started "$cmd"
  }
  _ce_osc4545_precmd() { local ec=$?; _ce_osc4545_cwd; _ce_osc4545_prompt_begins; _ce_osc4545_prompt_ends; _ce_osc4545_command_exited "$ec"; }
  if [ -z "${PROMPT_COMMAND:-}" ]; then
    PROMPT_COMMAND="_ce_osc4545_precmd"
  else
    PROMPT_COMMAND="_ce_osc4545_precmd;${PROMPT_COMMAND}"
  fi
  trap '_ce_osc4545_preexec_invoke_exec' DEBUG
fi
# ---- end ContainEye OSC integration ----
"""#
    }

    /// Part 1: sent immediately — disables PTY echo so the payload is never printed.
    /// This line IS echoed once (one short line: "stty -echo"), which part 2 erases.
    static func installPreamble() -> String {
        "stty -echo 2>/dev/null\n"
    }

    /// Part 2: sent after 150 ms so stty has taken effect.
    /// Runs silently (echo is off), installs shell integration, restores echo,
    /// then moves up one line and erases it — removing the visible "stty -echo" line.
    static func installPayload() -> String {
        let payload = Data(script().utf8).base64EncodedString()
        return "__ce_s=$(printf '%s' \(payload) | base64 --decode 2>/dev/null || printf '%s' \(payload) | base64 -d 2>/dev/null || printf '%s' \(payload) | base64 -D 2>/dev/null); [ -n \"$__ce_s\" ] && eval \"$__ce_s\" >/dev/null 2>&1; unset __ce_s; stty echo 2>/dev/null; printf '\\033[A\\033[2K'\n"
    }

}
