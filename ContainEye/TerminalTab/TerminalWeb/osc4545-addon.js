(function () {
  const TERMIUS_OSC_ID = 4545;

  function decodeBase64Utf8(value) {
    try {
      const bytes = Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
      return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    } catch (error) {
      return { error: String(error) };
    }
  }

  function parsePayload(payload) {
    if (payload.startsWith("SetCwd;")) {
      return { type: "SetCwd", value: payload.slice("SetCwd;".length) };
    }
    if (payload === "ShellPromptBegins") {
      return { type: "ShellPromptBegins" };
    }
    if (payload === "ShellPromptEnds") {
      return { type: "ShellPromptEnds" };
    }
    if (payload.startsWith("CommandStarted;")) {
      return { type: "CommandStarted", value: payload.slice("CommandStarted;".length) };
    }
    if (payload.startsWith("CommandExited;")) {
      return { type: "CommandExited", value: payload.slice("CommandExited;".length) };
    }

    return { type: "Unknown", raw: payload };
  }

  class Osc4545Addon {
    constructor(postBridge) {
      this.postBridge = postBridge;
      this.disposable = null;
    }

    activate(terminal) {
      this.disposable = terminal.parser.registerOscHandler(TERMIUS_OSC_ID, (payload) => {
        const parsed = parsePayload(payload);

        switch (parsed.type) {
          case "SetCwd": {
            const decoded = decodeBase64Utf8(parsed.value);
            if (typeof decoded === "object" && decoded.error) {
              this.postBridge("shell_integration_error", {
                source: "SetCwd",
                reason: "invalid_base64",
                details: decoded.error,
              });
            } else {
              this.postBridge("cwd_changed", { cwd: decoded });
            }
            break;
          }
          case "ShellPromptBegins": {
            const active = terminal.buffer.active;
            window.__cePromptBegin = {
              row: active.cursorY + active.baseY,
              col: active.cursorX,
            };
            this.postBridge("prompt_begins", {
              row: active.cursorY + active.baseY,
              col: active.cursorX,
            });
            break;
          }
          case "ShellPromptEnds": {
            const active = terminal.buffer.active;
            window.__cePromptEnd = {
              row: active.cursorY + active.baseY,
              col: active.cursorX,
            };
            this.postBridge("prompt_ends", {
              row: active.cursorY + active.baseY,
              col: active.cursorX,
            });
            break;
          }
          case "CommandStarted": {
            const decoded = decodeBase64Utf8(parsed.value);
            if (typeof decoded === "object" && decoded.error) {
              this.postBridge("shell_integration_error", {
                source: "CommandStarted",
                reason: "invalid_base64",
                details: decoded.error,
              });
            } else {
              this.postBridge("command_started", {
                cmd: decoded,
                timestampMs: Date.now(),
              });
            }
            break;
          }
          case "CommandExited": {
            this.postBridge("command_exited", {
              exitCode: parsed.value,
              timestampMs: Date.now(),
            });
            break;
          }
          default: {
            this.postBridge("shell_integration_error", {
              source: "OSC4545",
              reason: "unknown_token",
              details: parsed.raw,
            });
            break;
          }
        }

        return true;
      });
    }

    dispose() {
      if (this.disposable) {
        this.disposable.dispose();
      }
      this.disposable = null;
    }
  }

  window.Osc4545Addon = Osc4545Addon;
})();
