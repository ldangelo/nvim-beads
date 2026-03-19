# PRD: Enhanced Task List with Inline Actions

## Product Summary

### Problem Statement

The current `:Beads` task list view is primarily a **read-only display** with limited direct interactions. Users can navigate tasks (`j`/`k`), view details (`<CR>`), delete (`d`), filter (`f`), and search (`/`), but the most common task management operations — closing a task, changing its status, and changing its priority — require navigating away from the list into detail or editor views. This creates unnecessary friction in the most frequent workflows:

- **Closing a task**: No direct shortcut from the list. Must open detail view → then close from there, or use `:BeadsClose <id>` and type the full ID manually.
- **Changing status**: Must either open the detail view → edit → change status, or use `:BeadsUpdate <id> status <value>` with the full ID. The fuzzy finder shortcut (`<leader>bS`) prompts for a task ID as text input rather than operating on the currently-selected task.
- **Changing priority**: Same friction as status — requires leaving the list or typing full IDs.

### Solution Overview

Transform the task list into an **interactive action panel** where users can perform common operations directly on the selected (cursor-highlighted) task via single-key shortcuts. The list becomes the primary command center for task management, not just a navigation aid.

### Value Proposition

- **Reduced keystrokes**: Close a task in 1 key (`x`) instead of 5+ steps
- **Context preservation**: Stay in the task list while managing tasks — no window-switching
- **Discoverability**: A visible help line and `?` shortcut show all available actions
- **Vim-native UX**: Follows patterns from Neovim plugins like Trouble, Fugitive, and Oil.nvim where the list _is_ the interface

---

## User Analysis

### Target Users

1. **Developer using Beads for personal task tracking** — Manages 5–30 active tasks, wants fast triage without leaving their editor.
2. **AI coding agent** — Interacts with nvim-beads programmatically; benefits from simple, predictable command interface but primarily uses CLI. This PRD focuses on the human user.
3. **Team developer** — Uses Beads across a shared repo, needs to quickly scan and update task states during standup-style reviews.

### Personas

| Persona | Context | Pain Point |
|---------|---------|------------|
| **Solo dev** | Opens `:Beads` to review tasks at start of work session | Wants to close completed tasks and promote one to "in_progress" without leaving the list |
| **Triage reviewer** | Scans full task list to reprioritize | Needs to change priority on multiple tasks quickly — current flow requires opening each task individually |
| **End-of-session dev** | Wrapping up work, closing tasks | Has to remember task IDs or navigate detail views just to mark things done |

### Current Workflow (Before)

1. Open `:Beads` to see task list
2. Navigate to a task with `j`/`k`
3. Press `<CR>` to open detail view in a split
4. Press `e` to open the editor
5. Change the status/priority field
6. Press `<C-s>` to save
7. Close the editor split
8. Re-open `:Beads` or `<leader>br` to refresh
9. Repeat for next task

### Desired Workflow (After)

1. Open `:Beads` to see task list
2. Navigate to a task with `j`/`k`
3. Press `x` to close it — list refreshes inline
4. Navigate to another task
5. Press `s` to get a status picker — select "in_progress" — list refreshes inline
6. Press `p` to get a priority picker — select "P1" — list refreshes inline
7. Done — never left the list

---

## Goals & Non-Goals

### Goals

1. **G1**: Add single-key shortcuts for close, status change, and priority change directly from the task list view
2. **G2**: Provide inline `vim.ui.select` pickers for status and priority so users choose from valid options
3. **G3**: Auto-refresh the task list after each action so the display stays current
4. **G4**: Preserve cursor position after refresh so the user stays oriented
5. **G5**: Show a help/legend line (or `?` toggle) so keymaps are discoverable
6. **G6**: Add a visual confirmation (notification) after each action

### Success Criteria

- All 3 core actions (close, change status, change priority) can be performed from the task list with ≤2 keystrokes (action key + picker selection)
- Task list refreshes automatically after each action with cursor position preserved
- Existing keymaps (`q`, `<CR>`, `r`, `f`, `c`, `d`, `j`, `k`, `/`, `t`, `<`, `>`, `<Backspace>`) continue to work unchanged
- Help is accessible via `?` keypress

### Non-Goals

- **N1**: Bulk/multi-select operations (e.g., close 5 tasks at once) — deferred to a future iteration
- **N2**: Inline editing of task title or description from the list view — the editor split is appropriate for that
- **N3**: Drag-and-drop reordering — not applicable in terminal UI
- **N4**: Custom action menus or user-defined shortcuts — premature for v1

---

## Functional Requirements

### FR1: Close Task from List (`x`)

**Description**: Pressing `x` on a highlighted task in the list view closes the task immediately.

**Behavior**:
1. Extract the task ID from the current cursor line (using existing `task_lines_map`)
2. Prompt for confirmation via `vim.ui.select({ "Yes", "No" }, ...)` with message: `Close task <id>? (<title>)`
3. On "Yes": call `cli.close(id)`, show notification "Closed: <title>", refresh task list
4. On "No" or cancel: do nothing
5. After refresh, restore cursor to the same line number (or nearest task if the closed task was removed from the filtered view)

**Edge Cases**:
- Task is already closed → show notification "Task already closed" and skip
- Cursor is on a non-task line (header, separator) → do nothing
- CLI error → show error notification, do not refresh

### FR2: Change Status from List (`s`)

**Description**: Pressing `s` on a highlighted task opens a status picker.

**Behavior**:
1. Extract the task ID from the current cursor line
2. Show `vim.ui.select` with valid statuses: `{ "open", "in_progress", "closed", "blocked", "deferred" }`
3. Current status should be visually indicated (e.g., prefixed with `●` or `[current]`)
4. On selection: call `cli.update(id, { status = selected_status })`, show notification "Status → <status>: <title>", refresh task list
5. On cancel: do nothing
6. After refresh, restore cursor position

**Edge Cases**:
- User selects the current status → skip the update, no notification needed
- Cursor is on a non-task line → do nothing

### FR3: Change Priority from List (`p`)

**Description**: Pressing `p` on a highlighted task opens a priority picker.

**Behavior**:
1. Extract the task ID from the current cursor line
2. Show `vim.ui.select` with valid priorities: `{ "P0", "P1", "P2", "P3", "P4" }` with labels:
   - `P0 — Critical`
   - `P1 — High`
   - `P2 — Medium`
   - `P3 — Low`
   - `P4 — Backlog`
3. Current priority should be visually indicated
4. On selection: call `cli.update(id, { priority = selected_priority })`, show notification "Priority → <priority>: <title>", refresh task list
5. On cancel: do nothing
6. After refresh, restore cursor position

**Edge Cases**:
- User selects the current priority → skip the update
- Cursor is on a non-task line → do nothing

### FR4: Quick Set In-Progress (`i`)

**Description**: Pressing `i` on a highlighted task immediately sets it to `in_progress` status (most common status transition — no picker needed).

**Behavior**:
1. Extract the task ID from the current cursor line
2. If task is already `in_progress` → show notification "Already in progress" and skip
3. Otherwise: call `cli.update(id, { status = "in_progress" })`, show notification "→ In Progress: <title>", refresh
4. Restore cursor position

### FR5: Help Toggle (`?`)

**Description**: Pressing `?` shows/hides a help section at the bottom of the task list buffer.

**Behavior**:
1. Toggle a help section appended to the task list buffer displaying all available keymaps
2. Help content:
   ```
   ─── Keymaps ──────────────────────────────
   <CR>  Show detail     x  Close task
   s     Set status      p  Set priority
   i     Start (→ in_progress)
   d     Delete task     r  Refresh
   f     Filter          c  Clear filters
   /     Search          ⌫  Clear search
   j/k   Navigate        t  Toggle sidebar
   </>   Sidebar width   ?  Toggle help
   q     Quit
   ```
3. When help is visible, pressing `?` again hides it
4. Help state is not persisted across sessions

### FR6: Cursor Position Preservation

**Description**: After any action that triggers a list refresh, the cursor should return to the same task (by ID) or the nearest task line.

**Behavior**:
1. Before refresh: save the task ID at the current cursor position (from `task_lines_map`)
2. After refresh: scan the new `task_lines_map` for the saved task ID
3. If found: set cursor to that line
4. If not found (task was removed from view): set cursor to the nearest task line (same line number, clamped to buffer bounds)

### FR7: Status Bar Enhancement

**Description**: Update the existing status bar at the top of the task list to include a hint about the `?` help key.

**Behavior**:
- Append `| ? for help` to the existing status bar line
- Example: `─ Tasks: 12/15 | Filters: Priority: P1 | ✓ Synced | ? for help ─────`

---

## Non-Functional Requirements

### Performance

- **NFR1**: All inline actions (close, status change, priority change) must complete and refresh the list in under 500ms on a project with ≤100 tasks
- **NFR2**: Cursor position restoration must be imperceptible (< 50ms after buffer update)
- **NFR3**: The `vim.ui.select` picker should appear within 100ms of the keypress

### Compatibility

- **NFR4**: Must work with both floating window and sidebar display modes
- **NFR5**: Must work with both `bd` (Python) and `br` (Rust) CLI backends
- **NFR6**: `vim.ui.select` pickers should work with Telescope, fzf-lua, and the built-in Neovim selector (dressing.nvim, etc.)

### Code Quality

- **NFR7**: New keymaps must be added to `ui_keymaps.lua` following the existing pattern
- **NFR8**: Task ID extraction should use the existing `task_lines_map` lookup (not regex parsing) when possible, falling back to regex for robustness
- **NFR9**: All new functions must have LuaDoc annotations matching the existing codebase style
- **NFR10**: New tests must be added to `tests/ui_keymaps_spec.lua` (or new test file) for each action

### Accessibility

- **NFR11**: All notifications must use `vim.notify` at appropriate log levels (INFO for success, WARN for no-op, ERROR for failures)
- **NFR12**: Keymap choices should be mnemonic (`x` = close/X-out, `s` = status, `p` = priority, `i` = in-progress, `?` = help)

---

## Acceptance Criteria

### AC1: Close Task from List

- [ ] Pressing `x` on a task line prompts for confirmation
- [ ] Confirming "Yes" closes the task via CLI and refreshes the list
- [ ] Confirming "No" or pressing `<Esc>` does nothing
- [ ] Already-closed tasks show "Task already closed" notification
- [ ] Cursor returns to the nearest task after refresh
- [ ] Non-task lines (headers, separators) are silently ignored

### AC2: Change Status from List

- [ ] Pressing `s` on a task line opens a `vim.ui.select` with all valid statuses
- [ ] Current status is indicated in the picker list
- [ ] Selecting a different status updates via CLI and refreshes
- [ ] Selecting the same status does nothing (no CLI call)
- [ ] Cursor is preserved after refresh

### AC3: Change Priority from List

- [ ] Pressing `p` on a task line opens a `vim.ui.select` with all priorities (P0–P4) with labels
- [ ] Current priority is indicated in the picker list
- [ ] Selecting a different priority updates via CLI and refreshes
- [ ] Selecting the same priority does nothing
- [ ] Cursor is preserved after refresh

### AC4: Quick In-Progress

- [ ] Pressing `i` on a task immediately sets status to `in_progress`
- [ ] If already `in_progress`, shows notification and skips
- [ ] List refreshes with cursor preserved

### AC5: Help Toggle

- [ ] Pressing `?` appends a help section to the buffer
- [ ] Pressing `?` again removes the help section
- [ ] Help content lists all available keymaps accurately
- [ ] Help does not interfere with task navigation

### AC6: Status Bar Hint

- [ ] Status bar includes `? for help` text
- [ ] Existing status bar content (count, filters, sync) is not disrupted

### AC7: Backward Compatibility

- [ ] All existing keymaps (`q`, `<CR>`, `r`, `f`, `c`, `d`, `j`, `k`, `/`, `<Backspace>`, `t`, `<`, `>`) work identically
- [ ] Existing commands (`:BeadsClose`, `:BeadsUpdate`) still work independently
- [ ] Floating window and sidebar modes both support all new actions

### AC8: Cursor Preservation

- [ ] After closing a task, cursor is on the nearest remaining task
- [ ] After changing status/priority, cursor remains on the same task
- [ ] If the task list is empty after an action, cursor is on line 1

### Test Scenarios

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| T1 | Close task from list | Open `:Beads`, navigate to task, press `x`, confirm "Yes" | Task closed, list refreshed, notification shown |
| T2 | Cancel close | Open `:Beads`, navigate to task, press `x`, select "No" | Nothing happens |
| T3 | Close on non-task line | Open `:Beads`, move cursor to header, press `x` | Nothing happens (no error) |
| T4 | Change status | Navigate to task, press `s`, select "in_progress" | Status updated, list refreshed, status symbol changes to `◐` |
| T5 | Change status (same) | Navigate to task with status "open", press `s`, select "open" | No CLI call, no notification |
| T6 | Change priority | Navigate to task, press `p`, select "P1 — High" | Priority updated, list shows `[P1]` |
| T7 | Quick in-progress | Navigate to open task, press `i` | Status changes to in_progress, symbol → `◐` |
| T8 | Quick in-progress (already) | Navigate to in_progress task, press `i` | "Already in progress" notification |
| T9 | Help toggle on | Press `?` | Help section appended to buffer |
| T10 | Help toggle off | Press `?` twice | Help section removed |
| T11 | Cursor after close | Close middle task in 5-task list | Cursor on next task (same line number) |
| T12 | Cursor after status change | Change status of 3rd task | Cursor stays on 3rd task |
| T13 | All existing keymaps | Open `:Beads`, test each existing keymap | All work unchanged |
| T14 | Sidebar mode | Enable sidebar, test all new actions | All actions work in sidebar |
| T15 | CLI error handling | Disconnect `bd` binary, try to close a task | Error notification, list unchanged |

---

## Implementation Notes

These notes are for developer reference during the TRD phase — they are **not** specifications.

### Keymap Conflict Check

Current task list keymaps that are already bound:
- `q`, `<CR>`, `r`, `f`, `c`, `d`, `j`, `k`, `/`, `<Backspace>`, `t`, `<`, `>`

New keymaps to add: `x`, `s`, `p`, `i`, `?`

**Conflict analysis**:
- `s` — Currently unbound in the task list. (Note: `s` is commonly "substitute" in Vim, but the buffer is non-modifiable, so this is safe.)
- `p` — Currently unbound. (Vim's paste, but buffer is non-modifiable.)
- `x` — Currently unbound. (Vim's delete char, but buffer is non-modifiable.)
- `i` — Currently unbound. (Vim's insert mode, but buffer is non-modifiable — `i` would normally be blocked anyway.)
- `?` — Currently unbound. (Vim's backward search, but acceptable tradeoff for help.)

All proposed keys are safe to bind in a `nofile`/non-modifiable buffer.

### Architecture Guidance

- Add new keymaps to `ui_keymaps.lua` → `setup_task_list_keymaps()`
- Helper function to get task at cursor: use `task_lines_map[current_line]` → look up task object in `current_tasks`
- Cursor preservation: wrap refresh calls with save/restore logic in `ui.lua`
- Help toggle: maintain a `help_visible` boolean in the ui_keymaps module or ui module state

### Files Likely Modified

1. `lua/beads/ui_keymaps.lua` — New keymap bindings
2. `lua/beads/ui.lua` — Cursor preservation logic, help toggle state, enhanced refresh
3. `lua/beads/ui_rendering.lua` — Help section rendering
4. `tests/ui_keymaps_spec.lua` — New test cases
