(function () {
  const bridge = window.webkit && window.webkit.messageHandlers
    ? window.webkit.messageHandlers.terminalBridge
    : null;

  function postBridge(type, payload) {
    bridge && bridge.postMessage({ type, payload: payload || {} });
  }

  function getSelectionMenuPoint(terminal) {
    const selection = terminal.getSelectionPosition();
    if (!selection) {
      return null;
    }

    const screen = terminal.element && terminal.element.querySelector
      ? (terminal.element.querySelector(".xterm-screen") || terminal.element)
      : null;
    if (!screen) {
      return null;
    }

    const dims = terminal._core && terminal._core._renderService && terminal._core._renderService.dimensions
      ? terminal._core._renderService.dimensions.css
      : null;
    const cellWidth = dims && dims.cell ? dims.cell.width : 0;
    const cellHeight = dims && dims.cell ? dims.cell.height : 0;
    if (!cellWidth || !cellHeight) {
      return null;
    }

    const rect = screen.getBoundingClientRect();
    const viewportY = terminal.buffer.active.viewportY || 0;
    const end = selection.end || selection.start;

    const col = Math.max(0, Math.min(terminal.cols - 1, end.x || 0));
    const rowInViewport = Math.max(0, Math.min(terminal.rows - 1, (end.y || 0) - viewportY));

    return {
      x: (col + 0.5) * cellWidth + (rect.left - terminal.element.getBoundingClientRect().left),
      y: (rowInViewport + 0.5) * cellHeight + (rect.top - terminal.element.getBoundingClientRect().top),
    };
  }

  function emitSelectionChanged(terminal) {
    const payload = {
      selection: terminal.getSelection(),
      hasSelection: terminal.hasSelection(),
    };

    const point = getSelectionMenuPoint(terminal);
    if (point) {
      payload.menuX = point.x;
      payload.menuY = point.y;
    }

    postBridge("selection_changed", payload);
  }

  function installTouchSelection(terminal) {
    const element = terminal.element;
    const supportsTouch = ("ontouchstart" in window) || ((navigator.maxTouchPoints || 0) > 0);
    if (!element || !supportsTouch) {
      return;
    }

    const state = {
      anchor: null,
      selecting: false,
      timerId: 0,
      startX: 0,
      startY: 0,
      hintShown: false,
    };

    function clearTimer() {
      if (state.timerId) {
        window.clearTimeout(state.timerId);
        state.timerId = 0;
      }
    }

    function getCell(touch) {
      const screen = element.querySelector(".xterm-screen") || element;
      const rect = screen.getBoundingClientRect();
      const dims = terminal._core && terminal._core._renderService && terminal._core._renderService.dimensions
        ? terminal._core._renderService.dimensions.css
        : null;
      const cellWidth = dims && dims.cell ? dims.cell.width : 0;
      const cellHeight = dims && dims.cell ? dims.cell.height : 0;
      if (!cellWidth || !cellHeight) {
        return null;
      }

      const col = Math.max(0, Math.min(terminal.cols - 1, Math.floor((touch.clientX - rect.left) / cellWidth)));
      const viewportRow = Math.max(0, Math.min(terminal.rows - 1, Math.floor((touch.clientY - rect.top) / cellHeight)));
      const row = (terminal.buffer.active.viewportY || 0) + viewportRow;

      return { row: row, col: col };
    }

    function applySelection(anchor, current) {
      const startIndex = (anchor.row * terminal.cols) + anchor.col;
      const endIndex = (current.row * terminal.cols) + current.col;
      const from = Math.min(startIndex, endIndex);
      const to = Math.max(startIndex, endIndex);
      const row = Math.floor(from / terminal.cols);
      const col = from % terminal.cols;
      const length = (to - from) + 1;

      terminal.select(col, row, length);
      emitSelectionChanged(terminal);
    }

    function endSelection() {
      clearTimer();
      state.selecting = false;
      state.anchor = null;
    }

    element.addEventListener("touchstart", function (event) {
      if (!event.touches || event.touches.length !== 1) {
        endSelection();
        return;
      }

      const touch = event.touches[0];
      const anchor = getCell(touch);
      if (!anchor) {
        return;
      }

      state.startX = touch.clientX;
      state.startY = touch.clientY;
      state.anchor = anchor;
      state.selecting = false;
      clearTimer();

      state.timerId = window.setTimeout(function () {
        if (!state.anchor) {
          return;
        }
        if (!state.hintShown) {
          postBridge("selection_hint", {
            message: "Press and hold, then move your finger to select",
          });
          state.hintShown = true;
        }
        state.selecting = true;
        applySelection(state.anchor, state.anchor);
      }, 260);
    }, { passive: true });

    element.addEventListener("touchmove", function (event) {
      if (!event.touches || event.touches.length !== 1) {
        endSelection();
        return;
      }

      const touch = event.touches[0];
      if (!state.selecting) {
        const movedFar = Math.abs(touch.clientX - state.startX) > 8 || Math.abs(touch.clientY - state.startY) > 8;
        if (movedFar) {
          clearTimer();
        }
        return;
      }

      const current = getCell(touch);
      if (!current || !state.anchor) {
        return;
      }

      event.preventDefault();
      applySelection(state.anchor, current);
    }, { passive: false });

    element.addEventListener("touchend", endSelection, { passive: true });
    element.addEventListener("touchcancel", endSelection, { passive: true });
  }

  function tokenizeShellLine(line) {
    const tokens = [];
    let current = "";
    let quote = null;
    let escaping = false;

    for (const char of line) {
      if (escaping) {
        current += char;
        escaping = false;
        continue;
      }

      if (quote) {
        if (char === quote) {
          quote = null;
        } else {
          if (char === "\\" && quote === "\"") {
            escaping = true;
            continue;
          }
          current += char;
        }
        continue;
      }

      if (char === "\\") {
        escaping = true;
        continue;
      }

      if (char === "\"" || char === "'") {
        quote = char;
        continue;
      }

      if (/\s/.test(char)) {
        if (current.length > 0) {
          tokens.push(current);
          current = "";
        }
        continue;
      }

      current += char;
    }

    if (escaping) {
      current += "\\";
    }

    if (current.length > 0) {
      tokens.push(current);
    }

    return tokens;
  }

  function isEditorLikeCommand(commandLine) {
    const tokens = tokenizeShellLine((commandLine || "").trim());
    if (tokens.length === 0) {
      return false;
    }

    let index = 0;
    if (tokens[index] === "sudo") {
      index += 1;
      while (index < tokens.length && tokens[index].startsWith("-")) {
        if (tokens[index] === "-u") {
          index += 2;
        } else {
          index += 1;
        }
      }
    }

    if (index >= tokens.length) {
      return false;
    }

    const command = tokens[index];
    if (!["open", "nano", "vim", "nvim"].includes(command)) {
      return false;
    }

    return tokens.length > (index + 1);
  }

  function getCurrentCommandLine(terminal) {
    const active = terminal.buffer && terminal.buffer.active;
    if (!active) {
      return "";
    }

    const cursorRow = active.baseY + active.cursorY;
    const cursorCol = active.cursorX;

    const promptEnd = window.__cePromptEnd;
    const startRow = (promptEnd && typeof promptEnd.row === "number")
      ? Math.min(promptEnd.row, cursorRow)
      : cursorRow;
    const startCol = (promptEnd && typeof promptEnd.col === "number" && startRow === promptEnd.row)
      ? promptEnd.col
      : 0;

    const parts = [];
    for (let row = startRow; row <= cursorRow; row += 1) {
      const line = active.getLine(row);
      if (!line) {
        continue;
      }

      let text = line.translateToString(true);
      if (row === startRow && startCol > 0) {
        text = text.slice(startCol);
      }
      if (row === cursorRow) {
        text = text.slice(0, cursorCol);
      }
      parts.push(text);
    }

    return parts.join("");
  }

  function bootstrap() {
    if (!window.Terminal || !window.FitAddon || !window.SearchAddon || !window.WebLinksAddon || !window.SerializeAddon || !window.Unicode11Addon || !window.Osc4545Addon) {
      postBridge("shell_integration_error", {
        source: "bootstrap",
        reason: "xterm_load_failed",
        details: "One or more xterm runtime assets are unavailable",
      });
      return;
    }

    const terminal = new window.Terminal({
      allowProposedApi: true,
      macOptionClickForcesSelection: true,
      rightClickSelectsWord: false,
      cursorBlink: false,
      scrollback: 6000,
      convertEol: false,
      fontFamily: "Menlo, SFMono-Regular, ui-monospace, monospace",
      fontSize: 13,
      logLevel: "off",
    });

    const fitAddon = new window.FitAddon.FitAddon();
    const searchAddon = new window.SearchAddon.SearchAddon();
    const serializeAddon = new window.SerializeAddon.SerializeAddon();
    const webLinksAddon = new window.WebLinksAddon.WebLinksAddon(function (event, url) {
      postBridge("open_external_link", {
        url: url,
        metaKey: !!event.metaKey,
        ctrlKey: !!event.ctrlKey,
      });
    });
    const unicode11Addon = new window.Unicode11Addon.Unicode11Addon();
    const oscAddon = new window.Osc4545Addon(postBridge);

    terminal.loadAddon(oscAddon);
    terminal.open(document.getElementById("terminal"));

    terminal.loadAddon(fitAddon);
    terminal.loadAddon(searchAddon);
    terminal.loadAddon(serializeAddon);
    terminal.loadAddon(webLinksAddon);
    terminal.loadAddon(unicode11Addon);
    terminal.unicode.activeVersion = "11";

    fitAddon.fit();
    installTouchSelection(terminal);

    terminal.onData(function (data) {
      postBridge("terminal_data", { data: data });
    });

    terminal.onSelectionChange(function () {
      emitSelectionChanged(terminal);
    });

    terminal.attachCustomKeyEventHandler(function (event) {
      if (event.type !== "keydown") {
        return true;
      }
      if (event.key !== "Enter") {
        return true;
      }
      if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) {
        return true;
      }

      const commandLine = getCurrentCommandLine(terminal).trim();
      if (!isEditorLikeCommand(commandLine)) {
        return true;
      }

      postBridge("editor_command_entered", { line: commandLine });
      return false;
    });

    window.addEventListener("resize", function () {
      fitAddon.fit();
      postBridge("terminal_resized", {
        cols: terminal.cols,
        rows: terminal.rows,
      });
    });

    window.terminalHost = {
      write: function (data) {
        terminal.write(data);
      },
      focus: function () {
        terminal.focus();
      },
      applySuggestion: function (text) {
        terminal.input("\u0015", true);
        terminal.input(text, true);
      },
      resizeAndSync: function () {
        fitAddon.fit();
        postBridge("terminal_resized", {
          cols: terminal.cols,
          rows: terminal.rows,
        });
      },
      clearSelection: function () {
        terminal.clearSelection();
      },
      selectAll: function () {
        terminal.selectAll();
      },
      submitEnter: function () {
        terminal.input("\r", true);
      },
      getSelectionText: function () {
        return terminal.getSelection() || "";
      },
      findNext: function (text) {
        return searchAddon.findNext(text);
      },
      findPrevious: function (text) {
        return searchAddon.findPrevious(text);
      },
      serialize: function (scrollback) {
        const sc = typeof scrollback === "number" ? scrollback : 1200;
        return serializeAddon.serialize({ scrollback: sc });
      },
    };

    postBridge("terminal_ready", {
      cols: terminal.cols,
      rows: terminal.rows,
      oscNamespace: 4545,
    });
  }

  try {
    bootstrap();
  } catch (error) {
    postBridge("shell_integration_error", {
      source: "bootstrap",
      reason: "xterm_load_failed",
      details: String(error),
    });
  }
})();
