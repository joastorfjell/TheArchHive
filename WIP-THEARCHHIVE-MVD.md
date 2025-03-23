## MVDs for Arch Hivemind Project Components

### 1. Conversational AI (Claude)
- **Goal**: A basic Neovim plugin where Claude chats with the user and responds to simple prompts.
- **MVD Features**:
  - Claude greets the user in a Neovim split window: “Hey, I’m Claude! What’s your Arch setup goal?”
  - Responds to one question (e.g., “What packages should I install for coding?”) with a hardcoded suggestion (e.g., “Try `neovim`, `gcc`, and `python`!”).
- **Tech**:
  - Neovim with a Lua plugin.
  - Mock Claude API response (no real API yet—just static text).
- **Demo Outcome**: User opens Neovim, chats with Claude, and gets a basic reply.
- **Why**: Proves Claude can live in Neovim and talk to us—Chapter 1’s foundation.

---

### 2. Model Context Protocol (MCP)
- **Goal**: A simple MCP server that feeds Claude one piece of system info.
- **MVD Features**:
  - MCP server runs locally, grabs CPU usage (e.g., via `top` or `/proc/stat`).
  - Claude in Neovim says, “Your CPU usage is X%—want to optimize it?” (X is the real value).
- **Tech**:
  - Python script for the MCP server, exposing a REST endpoint (e.g., `localhost:5000/cpu`).
  - Neovim plugin pulls this data with a basic HTTP request.
- **Demo Outcome**: Claude shows live CPU usage in Neovim.
- **Why**: Tests MCP’s ability to connect Claude to the system—Chapter 2’s starting point.

---

### 3. ClaudeScript
- **Goal**: A minimal ClaudeScript encoder/decoder for a single system detail.
- **MVD Features**:
  - Encodes one package (e.g., `neovim-0.9`) into ClaudeScript: `p:neovim-0.9`.
  - Claude in Neovim can decode it back and say, “You’ve got Neovim 0.9 installed!”
  - Spec lives in a local text file (e.g., `claudescript.txt`).
- **Tech**:
  - Python script in the MCP server to encode/decode.
  - Neovim plugin reads the spec file and parses the string.
- **Demo Outcome**: ClaudeScript encodes a package, and Claude reads it in Neovim.
- **Why**: Kickstarts ClaudeScript as a shared language—also Chapter 2’s early win.

---

### 4. System Snapshot System (SSS)
- **Goal**: A basic snapshot of one system aspect in ClaudeScript.
- **MVD Features**:
  - Script grabs one installed package (e.g., `pacman -Qe | grep neovim`).
  - Outputs it in ClaudeScript: `p:neovim-0.9`.
  - Claude displays it in Neovim: “Here’s your snapshot: Neovim 0.9.”
- **Tech**:
  - Bash/Python script for snapshot collection.
  - Ties into the MCP server to pass the data.
- **Demo Outcome**: User sees a tiny snapshot in Neovim via Claude.
- **Why**: Proves SSS can capture and share system data—Chapter 5’s first step.

---

### 5. Community Hub (“The Arch Hive”)
- **Goal**: A barebones server to store and retrieve a snapshot.
- **MVD Features**:
  - User uploads a ClaudeScript snapshot (e.g., `p:neovim-0.9`) via a simple web form.
  - Another user can download it and see it in Neovim via Claude: “Someone shared Neovim 0.9!”
- **Tech**:
  - Flask app with a `/upload` and `/get` endpoint.
  - SQLite database to store one snapshot.
- **Demo Outcome**: Upload a snapshot, retrieve it elsewhere—basic sharing works.
- **Why**: Gets The Arch Hive off the ground—Chapter 6’s core concept.

---

### 6. Troubleshooting & Version Control
- **Goal**: Track one config file with Git and rollback if needed.
- **MVD Features**:
  - Claude monitors a test file (e.g., `~/.testconfig`).
  - User changes it (e.g., adds “hello=world”); Claude commits it to Git.
  - Claude can revert it with a prompt: “Want to undo that change?”
- **Tech**:
  - Git initialized in a test directory.
  - Python script in MCP to handle commits/rollbacks.
- **Demo Outcome**: Edit a file, Claude saves it, and reverts on command.
- **Why**: Shows safe config management—Chapter 4’s proof of concept.

---

### 7. Visual Dashboard
- **Goal**: A terminal dashboard showing one system stat with a default theme vibe.
- **MVD Features**:
  - Displays CPU usage from MCP in a simple TUI.
  - Uses a clean, “blank canvas” look (mimicking GTK Adwaita’s simplicity).
- **Tech**:
  - Python with `rich` for a terminal UI.
  - Pulls data from the MCP server.
- **Demo Outcome**: Run a script, see CPU usage in a neat terminal box.
- **Why**: Tests the dashboard’s UX and theme—Chapter 7’s starting point.

---

### 8. Software Optimization
- **Goal**: Tweak one software package with a runtime config change.
- **MVD Features**:
  - Claude spots `neovim` in the SSS snapshot.
  - Suggests a runtime tweak: “Add `set number` to `~/.config/nvim/init.vim`?”
  - Applies it if approved, encodes it in ClaudeScript: `r:set number`.
- **Tech**:
  - Python script to edit the config file.
  - Ties into MCP and ClaudeScript.
- **Demo Outcome**: Claude tweaks Neovim and shares the tweak.
- **Why**: Proves optimization basics—Chapter 10’s first taste.

---

## Development Workflow Tie-In
These MVDs align with our vibe-coding workflow from the start:
- **Modular Chunks**: Each MVD is a small, standalone piece we can build and test independently.
- **AI Lifting**: Claude (or its mock version) drives the demos, with us guiding via prompts.
- **Git Checkpoints**: We’ll commit each MVD as a feature branch (e.g., `chapter-1-claude-plugin`).
- **Documentation**: Each MVD gets a quick note in a `docs/mvds.md` file, keeping context clear.