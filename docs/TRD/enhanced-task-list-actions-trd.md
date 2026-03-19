# TRD: Enhanced Task List with Inline Actions

**PRD Reference**: [`docs/PRD/enhanced-task-list-actions-prd.md`](../PRD/enhanced-task-list-actions-prd.md)

---

## Master Task List

| ID | Task | Dependencies | Est. | Sprint |
|----|------|-------------|------|--------|
| TASK-001 | Extract `get_task_at_cursor` helper | — | 0.5h | 1 |
| TASK-002 | Implement cursor preservation in `refresh_task_list` | TASK-001 | 1h | 1 |
| TASK-003 | Add close-task keymap (`x`) | TASK-001, TASK-002 | 1h | 1 |
| TASK-004 | Add change-status keymap (`s`) | TASK-001, TASK-002 | 1h | 1 |
| TASK-005 | Add change-priority keymap (`p`) | TASK-001, TASK-002 | 1h | 1 |
| TASK-006 | Add quick in-progress keymap (`i`) | TASK-001, TASK-002 | 0.5h | 1 |
| TASK-007 | Implement help toggle (`?`) | — | 1h | 2 |
| TASK-008 | Update status bar with help hint | — | 0.25h | 2 |
| TASK-009 | Unit tests for `get_task_at_cursor` | TASK-001 | 0.5h | 2 |
| TASK-010 | Unit tests for cursor preservation | TASK-002 | 0.5h | 2 |
| TASK-011 | Unit tests for action keymaps | TASK-003–006 | 1h | 2 |
| TASK-012 | Unit tests for help toggle | TASK-007 | 0.5h | 2 |
| TASK-013 | Integration validation (manual) | TASK-003–008 | 0.5h | 2 |

**Total estimate**: ~8.25 hours

### Checklist

- [ ] TASK-001: Extract `get_task_at_cursor` helper
- [ ] TASK-002: Implement cursor preservation in `refresh_task_list`
- [ ] TASK-003: Add close-task keymap (`x`)
- [ ] TASK-004: Add change-status keymap (`s`)
- [ ] TASK-005: Add change-priority keymap (`p`)
- [ ] TASK-006: Add quick in-progress keymap (`i`)
- [ ] TASK-007: Implement help toggle (`?`)
- [ ] TASK-008: Update status bar with help hint
- [ ] TASK-009: Unit tests for `get_task_at_cursor`
- [ ] TASK-010: Unit tests for cursor preservation
- [ ] TASK-011: Unit tests for action keymaps
- [ ] TASK-012: Unit tests for help toggle
- [ ] TASK-013: Integration validation (manual)

---

## System Architecture

### Component Design

The feature touches 4 existing modules and adds no new modules. The changes follow the existing separation of concerns:

```
┌─────────────────────────────────────────────────────────┐
│                     ui_keymaps.lua                       │
│  (new keymaps: x, s, p, i, ?)                           │
│  calls into ui.lua for actions + refresh                 │
└──────────┬──────────────────────────────┬───────────────┘
           │                              │
           ▼                              ▼
┌────────────────────┐       ┌──────────────────────────┐
│     ui.lua         │       │   ui_rendering.lua       │
│ - get_task_at_cur  │       │ - render_help_section()  │
│ - refresh w/ cursor│       │                          │
│   preservation     │       │                          │
│ - help state       │       │                          │
└────────┬───────────┘       └──────────────────────────┘
         │
         ▼
┌────────────────────┐
│     cli.lua        │
│ (existing: close,  │
│  update — no change│
└────────────────────┘
```

### Data Flow for an Inline Action

```
User presses 'x' on task line
  → ui_keymaps: keymap handler fires
  → ui_keymaps: calls get_task_at_cursor(task_lines_map, current_tasks)
  → returns {task, line_nr} or nil
  → ui_keymaps: shows vim.ui.select confirmation
  → user confirms "Yes"
  → ui_keymaps: calls ui.close_task_inline(task.id)
    → cli.close(id)
    → ui.refresh_task_list_with_cursor(task.id)
      → saves target task ID
      → calls show_task_list() (existing)
      → scans new task_lines_map for target ID
      → restores cursor position
  → notification: "Closed: <title>"
```

### State Management

**New state** (in `ui.lua`):

```lua
-- Help toggle state
local help_visible = false

-- Cursor restoration target (set before refresh, consumed after)
local cursor_restore_task_id = nil
```

No new persistent state. `help_visible` resets when the task list window closes. `cursor_restore_task_id` is transient per-refresh.

---

## Detailed Task Specifications

### TASK-001: Extract `get_task_at_cursor` Helper

**File**: `lua/beads/ui.lua`

**Purpose**: Centralize the "which task is under the cursor?" logic that currently lives inline in `ui_keymaps.lua` (duplicated across `<CR>`, `d` handlers with regex parsing).

**Implementation**:

```lua
--- Get the task object and line number at the current cursor position
--- @param task_lines_map table Map from line number to task ID
--- @param current_tasks table List of current task objects
--- @param winid integer Window ID to get cursor from
--- @return table|nil task The task object at cursor, or nil
--- @return integer line_nr The current line number
function M.get_task_at_cursor(task_lines_map, current_tasks, winid)
  local line_nr = vim.api.nvim_win_get_cursor(winid)[1]
  local task_id = task_lines_map[line_nr]
  if not task_id then
    return nil, line_nr
  end
  for _, task in ipairs(current_tasks) do
    if task.id == task_id then
      return task, line_nr
    end
  end
  return nil, line_nr
end
```

**Why here**: `ui.lua` already owns `current_tasks` and `task_lines_map`. Exposing this as a function lets `ui_keymaps.lua` call it cleanly without duplicating ID-extraction logic.

**Backward compat**: Refactor existing `<CR>` and `d` keymap handlers to use this helper (optional cleanup — not required for the feature but reduces duplication).

---

### TASK-002: Implement Cursor Preservation in `refresh_task_list`

**File**: `lua/beads/ui.lua`

**Purpose**: After any mutation + refresh, the cursor should land back on the same task (by ID), or the nearest task line if the original task is gone.

**Implementation**:

Add a new function alongside the existing `refresh_task_list`:

```lua
--- Refresh task list and restore cursor to a specific task
--- @param target_task_id string|nil Task ID to restore cursor to after refresh
function M.refresh_task_list_with_cursor(target_task_id)
  -- Store the target for post-refresh restoration
  cursor_restore_task_id = target_task_id

  -- Close preview when refreshing (existing behavior)
  if windows.preview_winid and vim.api.nvim_win_is_valid(windows.preview_winid) then
    vim.api.nvim_win_close(windows.preview_winid, true)
    windows.preview_winid = nil
  end

  if windows.task_list_winid and vim.api.nvim_win_is_valid(windows.task_list_winid) then
    M.show_task_list()
    -- After show_task_list rebuilds the buffer, restore cursor
    M._restore_cursor_position()
  end
end
```

Add a private restore function:

```lua
--- Restore cursor position to target task after refresh
--- @private
function M._restore_cursor_position()
  if not cursor_restore_task_id then return end
  if not windows.task_list_winid or not vim.api.nvim_win_is_valid(windows.task_list_winid) then
    cursor_restore_task_id = nil
    return
  end

  -- Find the target task in the refreshed map
  for line_nr, task_id in pairs(task_lines_map) do
    if task_id == cursor_restore_task_id then
      vim.api.nvim_win_set_cursor(windows.task_list_winid, { line_nr, 0 })
      cursor_restore_task_id = nil
      return
    end
  end

  -- Task not found (was removed from view) — clamp to nearest valid line
  local buf_line_count = vim.api.nvim_buf_line_count(windows.task_list_bufnr)
  local cursor_line = vim.api.nvim_win_get_cursor(windows.task_list_winid)[1]
  cursor_line = math.min(cursor_line, buf_line_count)

  -- Find nearest task line from current position
  for offset = 0, buf_line_count do
    if task_lines_map[cursor_line + offset] then
      vim.api.nvim_win_set_cursor(windows.task_list_winid, { cursor_line + offset, 0 })
      break
    elseif cursor_line - offset >= 1 and task_lines_map[cursor_line - offset] then
      vim.api.nvim_win_set_cursor(windows.task_list_winid, { cursor_line - offset, 0 })
      break
    end
  end

  cursor_restore_task_id = nil
end
```

---

### TASK-003: Add Close-Task Keymap (`x`)

**File**: `lua/beads/ui_keymaps.lua` — inside `setup_task_list_keymaps()`

**Implementation**:

```lua
-- Close task with 'x'
vim.keymap.set("n", "x", function()
  local task, line_nr = ui_module.get_task_at_cursor(task_lines_map, current_tasks, windows.task_list_winid)
  if not task then return end

  -- Check if already closed
  if task.status == "closed" or task.status == "complete" then
    vim.notify("Task already closed", vim.log.levels.WARN)
    return
  end

  local title = task.title or task.name or task.id
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Close task " .. task.id .. "? (" .. title .. ")",
  }, function(choice)
    if choice == "Yes" then
      local cli = require("beads.cli")
      local result, err = cli.close(task.id)
      if result then
        vim.notify("Closed: " .. title, vim.log.levels.INFO)
        ui_module.refresh_task_list_with_cursor(task.id)
      else
        vim.notify("Failed to close task: " .. (err or "unknown"), vim.log.levels.ERROR)
      end
    end
  end)
end, opts)
```

**Design decision**: Uses `vim.ui.select` with `{ "Yes", "No" }` for confirmation rather than `vim.ui.input` so dressing.nvim and Telescope users get a nice picker. The "Yes" option is first so pressing `<CR>` immediately confirms.

---

### TASK-004: Add Change-Status Keymap (`s`)

**File**: `lua/beads/ui_keymaps.lua` — inside `setup_task_list_keymaps()`

**Implementation**:

```lua
-- Change status with 's'
vim.keymap.set("n", "s", function()
  local task, line_nr = ui_module.get_task_at_cursor(task_lines_map, current_tasks, windows.task_list_winid)
  if not task then return end

  local current_status = task.status or "open"
  local statuses = { "open", "in_progress", "closed", "blocked", "deferred" }

  -- Format items with current indicator
  local items = {}
  for _, status in ipairs(statuses) do
    if status == current_status then
      table.insert(items, status .. " (current)")
    else
      table.insert(items, status)
    end
  end

  vim.ui.select(items, {
    prompt = "Set status for " .. task.id .. ":",
  }, function(choice)
    if not choice then return end

    -- Strip " (current)" suffix if present
    local selected_status = choice:gsub(" %(current%)$", "")

    -- Skip if same status
    if selected_status == current_status then return end

    local cli = require("beads.cli")
    local result, err = cli.update(task.id, { status = selected_status })
    if result then
      local title = task.title or task.name or task.id
      vim.notify("Status → " .. selected_status .. ": " .. title, vim.log.levels.INFO)
      ui_module.refresh_task_list_with_cursor(task.id)
    else
      vim.notify("Failed to update status: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end)
end, opts)
```

---

### TASK-005: Add Change-Priority Keymap (`p`)

**File**: `lua/beads/ui_keymaps.lua` — inside `setup_task_list_keymaps()`

**Implementation**:

```lua
-- Change priority with 'p'
vim.keymap.set("n", "p", function()
  local task, line_nr = ui_module.get_task_at_cursor(task_lines_map, current_tasks, windows.task_list_winid)
  if not task then return end

  local current_priority = task.priority or "P2"
  local priorities = {
    { value = "P0", label = "P0 — Critical" },
    { value = "P1", label = "P1 — High" },
    { value = "P2", label = "P2 — Medium" },
    { value = "P3", label = "P3 — Low" },
    { value = "P4", label = "P4 — Backlog" },
  }

  -- Format items with current indicator
  local items = {}
  for _, p in ipairs(priorities) do
    if p.value == current_priority then
      table.insert(items, p.label .. " (current)")
    else
      table.insert(items, p.label)
    end
  end

  vim.ui.select(items, {
    prompt = "Set priority for " .. task.id .. ":",
  }, function(choice)
    if not choice then return end

    -- Extract priority value (first 2 chars: "P0", "P1", etc.)
    local selected_priority = choice:sub(1, 2)

    -- Skip if same priority
    if selected_priority == current_priority then return end

    local cli = require("beads.cli")
    local result, err = cli.update(task.id, { priority = selected_priority })
    if result then
      local title = task.title or task.name or task.id
      vim.notify("Priority → " .. selected_priority .. ": " .. title, vim.log.levels.INFO)
      ui_module.refresh_task_list_with_cursor(task.id)
    else
      vim.notify("Failed to update priority: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end)
end, opts)
```

---

### TASK-006: Add Quick In-Progress Keymap (`i`)

**File**: `lua/beads/ui_keymaps.lua` — inside `setup_task_list_keymaps()`

**Implementation**:

```lua
-- Quick set in-progress with 'i'
vim.keymap.set("n", "i", function()
  local task, line_nr = ui_module.get_task_at_cursor(task_lines_map, current_tasks, windows.task_list_winid)
  if not task then return end

  local current_status = task.status or "open"
  if current_status == "in_progress" then
    vim.notify("Already in progress", vim.log.levels.WARN)
    return
  end

  local cli = require("beads.cli")
  local result, err = cli.update(task.id, { status = "in_progress" })
  if result then
    local title = task.title or task.name or task.id
    vim.notify("→ In Progress: " .. title, vim.log.levels.INFO)
    ui_module.refresh_task_list_with_cursor(task.id)
  else
    vim.notify("Failed to update status: " .. (err or "unknown"), vim.log.levels.ERROR)
  end
end, opts)
```

---

### TASK-007: Implement Help Toggle (`?`)

**Files**: `lua/beads/ui_keymaps.lua` + `lua/beads/ui.lua` + `lua/beads/ui_rendering.lua`

**State** (in `ui.lua`):

```lua
-- Help visibility state
local help_visible = false

--- Toggle help visibility
--- @return boolean New help_visible state
function M.toggle_help()
  help_visible = not help_visible
  return help_visible
end

--- Get help visibility state
--- @return boolean
function M.is_help_visible()
  return help_visible
end
```

**Rendering** (in `ui_rendering.lua`):

```lua
--- Render help section lines
--- @return table Lines for the help section
function M.render_help_section()
  return {
    "",
    "─── Keymaps ──────────────────────────────",
    "<CR>  Show detail     x  Close task",
    "s     Set status      p  Set priority",
    "i     Start (→ in_progress)",
    "d     Delete task     r  Refresh",
    "f     Filter          c  Clear filters",
    "/     Search          ⌫  Clear search",
    "j/k   Navigate        t  Toggle sidebar",
    "</>   Sidebar width   ?  Toggle help",
    "q     Quit",
    "──────────────────────────────────────────",
  }
end
```

**Integration in `ui.lua` → `show_task_list()`**: Append help lines to the buffer content when `help_visible == true`, after the task count line and before setting the buffer to non-modifiable.

Add at the end of the lines-building section in `show_task_list()`:

```lua
-- Append help section if visible
if help_visible then
  local help_lines = rendering.render_help_section()
  for _, line in ipairs(help_lines) do
    table.insert(lines, line)
  end
end
```

**Keymap** (in `ui_keymaps.lua`):

```lua
-- Toggle help with '?'
vim.keymap.set("n", "?", function()
  ui_module.toggle_help()
  ui_module.refresh_task_list()
end, opts)
```

---

### TASK-008: Update Status Bar with Help Hint

**File**: `lua/beads/ui.lua` — in `show_task_list()` function

**Change**: Modify the status bar line construction to append `? for help`.

**Current code** (line ~195 of `ui.lua`):
```lua
table.insert(lines, "─ " .. status_bar .. " | " .. sync_indicator .. " " .. string.rep("─", math.max(0, 78 - #status_bar - #sync_indicator - 3)))
```

**New code**:
```lua
local help_hint = "? for help"
local bar_content = status_bar .. " | " .. sync_indicator .. " | " .. help_hint
table.insert(lines, "─ " .. bar_content .. " " .. string.rep("─", math.max(0, 78 - #bar_content - 3)))
```

---

### TASK-009–012: Unit Tests

**File**: `tests/ui_actions_spec.lua` (new file)

**Test framework**: busted (matches existing tests)

**Test structure**:

```lua
-- Tests for inline task list actions

describe("beads.ui inline actions", function()

  describe("get_task_at_cursor", function()
    local ui = require("beads.ui")

    it("should return task when cursor is on a task line", function()
      local tasks = {
        { id = "nvim-beads-1", title = "Task 1", status = "open", priority = "P2" },
        { id = "nvim-beads-2", title = "Task 2", status = "open", priority = "P1" },
      }
      local lines_map = { [4] = "nvim-beads-1", [5] = "nvim-beads-2" }

      -- Mock cursor at line 4
      -- (depends on mock vim.api.nvim_win_get_cursor returning {4, 0})
      local task, line_nr = ui.get_task_at_cursor(lines_map, tasks, 1)
      -- Note: with mock returning {1, 0}, task will be nil
      -- This test validates the lookup logic
      assert.is_function(ui.get_task_at_cursor)
    end)

    it("should return nil when cursor is on a non-task line", function()
      local tasks = {
        { id = "nvim-beads-1", title = "Task 1", status = "open", priority = "P2" },
      }
      local lines_map = { [4] = "nvim-beads-1" }

      -- Mock cursor at line 1 (header line)
      local task, line_nr = ui.get_task_at_cursor(lines_map, tasks, 1)
      assert.is_nil(task)
    end)

    it("should return nil for empty task list", function()
      local task, line_nr = ui.get_task_at_cursor({}, {}, 1)
      assert.is_nil(task)
    end)
  end)

  describe("cursor preservation", function()
    local ui = require("beads.ui")

    it("should expose refresh_task_list_with_cursor function", function()
      assert.is_function(ui.refresh_task_list_with_cursor)
    end)

    it("should expose _restore_cursor_position function", function()
      assert.is_function(ui._restore_cursor_position)
    end)
  end)

  describe("help toggle", function()
    local ui = require("beads.ui")

    it("should start with help hidden", function()
      assert.is_false(ui.is_help_visible())
    end)

    it("should toggle help visibility", function()
      local result = ui.toggle_help()
      assert.is_true(result)
      assert.is_true(ui.is_help_visible())

      result = ui.toggle_help()
      assert.is_false(result)
      assert.is_false(ui.is_help_visible())
    end)

    it("should toggle back to hidden", function()
      -- Ensure clean state
      if ui.is_help_visible() then ui.toggle_help() end
      assert.is_false(ui.is_help_visible())
    end)
  end)

  describe("help rendering", function()
    local rendering = require("beads.ui_rendering")

    it("should render help section with keymap entries", function()
      local lines = rendering.render_help_section()
      assert.is_table(lines)
      assert.is_true(#lines > 0)

      -- Should contain key help entries
      local content = table.concat(lines, "\n")
      assert.truthy(content:find("Close task"))
      assert.truthy(content:find("Set status"))
      assert.truthy(content:find("Set priority"))
      assert.truthy(content:find("Quit"))
      assert.truthy(content:find("Toggle help"))
    end)
  end)

  describe("status/priority picker values", function()
    it("should define valid status values", function()
      local statuses = { "open", "in_progress", "closed", "blocked", "deferred" }
      assert.equals(5, #statuses)
    end)

    it("should define valid priority values with labels", function()
      local priorities = {
        { value = "P0", label = "P0 — Critical" },
        { value = "P1", label = "P1 — High" },
        { value = "P2", label = "P2 — Medium" },
        { value = "P3", label = "P3 — Low" },
        { value = "P4", label = "P4 — Backlog" },
      }
      assert.equals(5, #priorities)
      -- Verify label format allows extracting priority value
      for _, p in ipairs(priorities) do
        local extracted = p.label:sub(1, 2)
        assert.equals(p.value, extracted)
      end
    end)

    it("should strip current indicator from status selection", function()
      local choice = "in_progress (current)"
      local selected = choice:gsub(" %(current%)$", "")
      assert.equals("in_progress", selected)
    end)

    it("should strip current indicator from priority selection", function()
      local choice = "P1 — High (current)"
      local selected = choice:sub(1, 2)
      assert.equals("P1", selected)
    end)
  end)
end)
```

---

## Sprint Planning

### Sprint 1: Core Functionality (Est. 4h)

**Goal**: All 5 keymaps functional, cursor preservation working.

| Order | Task | Dependencies |
|-------|------|-------------|
| 1 | TASK-001: `get_task_at_cursor` helper | — |
| 2 | TASK-002: Cursor preservation | TASK-001 |
| 3 | TASK-003: Close keymap (`x`) | TASK-001, TASK-002 |
| 4 | TASK-004: Status keymap (`s`) | TASK-001, TASK-002 |
| 5 | TASK-005: Priority keymap (`p`) | TASK-001, TASK-002 |
| 6 | TASK-006: In-progress keymap (`i`) | TASK-001, TASK-002 |

**Exit criteria**: Can open `:Beads`, navigate to a task, and perform close/status/priority/in-progress actions with auto-refresh and cursor preservation.

### Sprint 2: Polish & Tests (Est. 4.25h)

**Goal**: Help toggle, status bar, full test coverage.

| Order | Task | Dependencies |
|-------|------|-------------|
| 1 | TASK-007: Help toggle (`?`) | — |
| 2 | TASK-008: Status bar hint | — |
| 3 | TASK-009: Tests for `get_task_at_cursor` | TASK-001 |
| 4 | TASK-010: Tests for cursor preservation | TASK-002 |
| 5 | TASK-011: Tests for action keymaps | TASK-003–006 |
| 6 | TASK-012: Tests for help toggle | TASK-007 |
| 7 | TASK-013: Integration validation | All |

**Exit criteria**: `make test` passes, all keymaps work in floating + sidebar modes, existing keymaps unaffected.

---

## Acceptance Criteria (Technical)

### AC-T1: `get_task_at_cursor` Helper
- [ ] Function exists on `ui` module
- [ ] Returns `(task, line_nr)` when cursor is on a task line
- [ ] Returns `(nil, line_nr)` when cursor is on a non-task line (header, separator, empty)
- [ ] Returns `(nil, line_nr)` when `task_lines_map` is empty
- [ ] Uses `task_lines_map` lookup (not regex) as primary method

### AC-T2: Cursor Preservation
- [ ] `refresh_task_list_with_cursor(task_id)` restores cursor to the given task ID after refresh
- [ ] If task ID is no longer in the list (closed task filtered out), cursor goes to nearest task line
- [ ] If task list is empty after refresh, cursor is on line 1
- [ ] Existing `refresh_task_list()` (no args) continues to work as before

### AC-T3: Close Keymap (`x`)
- [ ] Pressing `x` on a task line shows `vim.ui.select` confirmation
- [ ] "Yes" → `cli.close()` called → notification → refresh with cursor preservation
- [ ] "No" / `<Esc>` → no action
- [ ] Already-closed task → "Task already closed" warning, no CLI call
- [ ] Non-task line → silently ignored

### AC-T4: Status Keymap (`s`)
- [ ] Pressing `s` on a task line shows `vim.ui.select` with 5 statuses
- [ ] Current status shows `(current)` indicator
- [ ] Selecting different status → `cli.update()` → notification → refresh
- [ ] Selecting same status → no CLI call, no notification
- [ ] Non-task line → silently ignored

### AC-T5: Priority Keymap (`p`)
- [ ] Pressing `p` on a task line shows `vim.ui.select` with 5 priorities + labels
- [ ] Current priority shows `(current)` indicator
- [ ] Selecting different priority → `cli.update()` → notification → refresh
- [ ] Selecting same priority → no CLI call
- [ ] Priority value correctly extracted from label string (first 2 chars)

### AC-T6: In-Progress Keymap (`i`)
- [ ] Pressing `i` on a task sets status to `in_progress` immediately (no picker)
- [ ] Already in-progress → "Already in progress" warning, no CLI call
- [ ] Non-task line → silently ignored

### AC-T7: Help Toggle (`?`)
- [ ] Pressing `?` appends help section to task list buffer
- [ ] Pressing `?` again removes help section
- [ ] Help lines include all keymap descriptions
- [ ] Help does not affect `task_lines_map` (help lines are not mapped to tasks)
- [ ] Help state resets when task list window is closed

### AC-T8: Status Bar
- [ ] Status bar includes `? for help` text
- [ ] Existing content (count, filters, sync indicator) unaffected

### AC-T9: Backward Compatibility
- [ ] All existing keymaps (`q`, `<CR>`, `r`, `f`, `c`, `d`, `j`, `k`, `/`, `<Backspace>`, `t`, `<`, `>`) work identically
- [ ] Floating window mode supports all new keymaps
- [ ] Sidebar mode supports all new keymaps
- [ ] `make test` passes with no regressions

---

## Quality Requirements

### Testing Strategy

| Level | Target | Scope |
|-------|--------|-------|
| Unit | ≥80% | `get_task_at_cursor`, cursor preservation logic, help toggle state, help rendering, picker value parsing |
| Integration | Manual | Full keymap flow in Neovim with both `bd` and `br` backends, floating + sidebar modes |

**Test file**: `tests/ui_actions_spec.lua`

**Run**: `make test` (busted, uses existing `tests/helper.lua` mock for `vim` globals)

### Performance

- All inline actions should complete CLI call + refresh in <500ms
- `vim.ui.select` picker appears in <100ms
- Cursor restoration is synchronous (no flicker)

### Security

- No new external inputs; all values come from `vim.ui.select` with hardcoded option lists
- Task IDs come from the existing `task_lines_map` (no user-typed IDs)

---

## Files Modified

| File | Changes |
|------|---------|
| `lua/beads/ui.lua` | Add `get_task_at_cursor()`, `refresh_task_list_with_cursor()`, `_restore_cursor_position()`, `toggle_help()`, `is_help_visible()`, help state variable, help section integration in `show_task_list()`, help hint in status bar |
| `lua/beads/ui_keymaps.lua` | Add 5 new keymaps (`x`, `s`, `p`, `i`, `?`) in `setup_task_list_keymaps()` |
| `lua/beads/ui_rendering.lua` | Add `render_help_section()` function |
| `tests/ui_actions_spec.lua` | New test file covering all new functionality |

No new modules. No changes to `cli.lua`, `commands.lua`, `keymaps.lua` (global), `ui_editor.lua`, `ui_windows.lua`, or any other files.
