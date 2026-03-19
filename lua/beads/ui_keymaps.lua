-- Keyboard bindings for beads UI
-- Handles all keymaps for task list and other UI elements

local M = {}

--- Setup keymaps for task list window
--- @param ui_module table Reference to ui module (M) for calling UI functions
--- @param bufnr integer Buffer number for the task list
--- @param windows table Windows module reference
--- @param current_tasks table Current list of tasks
--- @param task_lines_map table Map from line number to task ID
function M.setup_task_list_keymaps(ui_module, bufnr, windows, current_tasks, task_lines_map)
  local opts = { noremap = true, silent = true, buffer = bufnr }

  -- Close window with 'q'
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(windows.task_list_winid, true)
    windows.task_list_winid = nil
  end, opts)

  -- Show task detail with '<CR>'
  vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_get_current_line()
    -- Extract task ID from line (format: "○ [P2] [id] status: title")
    -- Use specific pattern first to avoid matching title brackets
    local id = line:match("%[(nvim%-beads%-[^%]]+)%]")
    if not id then
      id = line:match("%[([^%]]+)%]%s*[^%[]*$")
    end
    if id then
      -- Close the preview window if open
      if windows.preview_winid and vim.api.nvim_win_is_valid(windows.preview_winid) then
        vim.api.nvim_win_close(windows.preview_winid, true)
        windows.preview_winid = nil
      end
      -- Close the task list window first
      if windows.task_list_winid and vim.api.nvim_win_is_valid(windows.task_list_winid) then
        vim.api.nvim_win_close(windows.task_list_winid, true)
        windows.task_list_winid = nil
      end
      ui_module.show_task_detail(id)
    end
  end, opts)

  -- Refresh task list with 'r'
  vim.keymap.set("n", "r", function()
    ui_module.refresh_task_list()
  end, opts)

  -- Filter controls with 'f'
  vim.keymap.set("n", "f", function()
    vim.ui.input({ prompt = "Filter (priority:P1,status:open,assignee:name): " }, function(input)
      if input and input ~= "" then
        ui_module.apply_filter_string(input)
        ui_module.refresh_task_list()
      end
    end)
  end, opts)

  -- Clear filters with 'c'
  vim.keymap.set("n", "c", function()
    ui_module.clear_filters()
    ui_module.refresh_task_list()
  end, opts)

  -- Delete task with 'd'
  vim.keymap.set("n", "d", function()
    local line = vim.api.nvim_get_current_line()
    -- Extract task ID from line (format: "○ [P2] [id] status: title")
    -- Use specific pattern first to avoid matching title brackets
    local id = line:match("%[(nvim%-beads%-[^%]]+)%]")
    if not id then
      id = line:match("%[([^%]]+)%]%s*[^%[]*$")
    end
    if id then
      ui_module.delete_task(id)
    end
  end, opts)

  -- Keyboard navigation down with 'j'
  vim.keymap.set("n", "j", function()
    -- Move down to next task line
    local current_line = vim.api.nvim_win_get_cursor(windows.task_list_winid)[1]
    local next_line = current_line + 1

    -- Skip non-task lines and find next task line
    while next_line <= vim.api.nvim_buf_line_count(windows.task_list_bufnr) do
      if task_lines_map[next_line] then
        vim.api.nvim_win_set_cursor(windows.task_list_winid, {next_line, 0})
        -- Show preview for the selected task
        local task_id = task_lines_map[next_line]
        if task_id then
          local task = nil
          for _, t in ipairs(current_tasks) do
            if t.id == task_id then
              task = t
              break
            end
          end
          if task then
            windows.show_task_preview(task)
          end
        end
        break
      end
      next_line = next_line + 1
    end
  end, opts)

  -- Keyboard navigation up with 'k'
  vim.keymap.set("n", "k", function()
    -- Move up to previous task line
    local current_line = vim.api.nvim_win_get_cursor(windows.task_list_winid)[1]
    local prev_line = current_line - 1

    -- Skip non-task lines and find previous task line
    while prev_line >= 1 do
      if task_lines_map[prev_line] then
        vim.api.nvim_win_set_cursor(windows.task_list_winid, {prev_line, 0})
        -- Show preview for the selected task
        local task_id = task_lines_map[prev_line]
        if task_id then
          local task = nil
          for _, t in ipairs(current_tasks) do
            if t.id == task_id then
              task = t
              break
            end
          end
          if task then
            windows.show_task_preview(task)
          end
        end
        break
      end
      prev_line = prev_line - 1
    end
  end, opts)

  -- Sidebar width adjustment with '<' (decrease)
  vim.keymap.set("n", "<", function()
    local beads = require("beads")
    local config = beads.get_config()
    if config.sidebar_enabled then
      local new_width = math.max(20, (config.sidebar_width or 40) - 2)
      config.sidebar_width = new_width
      beads.save_sidebar_config()
      if vim.api.nvim_win_is_valid(windows.task_list_winid) then
        vim.api.nvim_win_set_width(windows.task_list_winid, new_width)
      end
      vim.notify("Sidebar width: " .. new_width, vim.log.levels.INFO)
    end
  end, opts)

  -- Sidebar width adjustment with '>' (increase)
  vim.keymap.set("n", ">", function()
    local beads = require("beads")
    local config = beads.get_config()
    if config.sidebar_enabled then
      local new_width = math.min(120, (config.sidebar_width or 40) + 2)
      config.sidebar_width = new_width
      beads.save_sidebar_config()
      if vim.api.nvim_win_is_valid(windows.task_list_winid) then
        vim.api.nvim_win_set_width(windows.task_list_winid, new_width)
      end
      vim.notify("Sidebar width: " .. new_width, vim.log.levels.INFO)
    end
  end, opts)

  -- Toggle sidebar visibility with 't'
  vim.keymap.set("n", "t", function()
    ui_module.toggle_sidebar()
  end, opts)

  -- Search functionality with '/'
  vim.keymap.set("n", "/", function()
    vim.ui.input({ prompt = "Search tasks (or leave empty to clear): " }, function(input)
      if input == "" or input == nil then
        ui_module.set_search_query(nil)
      else
        ui_module.set_search_query(input)
      end
      -- Refresh task list with new search
      ui_module.refresh_task_list()
    end)
  end, opts)

  -- Clear search with '<Backspace>'
  vim.keymap.set("n", "<Backspace>", function()
    if ui_module.get_search_query() and ui_module.get_search_query() ~= "" then
      ui_module.set_search_query(nil)
      ui_module.refresh_task_list()
      vim.notify("Search cleared", vim.log.levels.INFO)
    end
  end, opts)

  -- Close task with 'x'
  vim.keymap.set("n", "x", function()
    local task, _ = ui_module.get_task_at_cursor(task_lines_map, current_tasks, windows.task_list_winid)
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

  -- Change status with 's'
  vim.keymap.set("n", "s", function()
    local task, _ = ui_module.get_task_at_cursor(task_lines_map, current_tasks, windows.task_list_winid)
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

  -- Change priority with 'p'
  vim.keymap.set("n", "p", function()
    local task, _ = ui_module.get_task_at_cursor(task_lines_map, current_tasks, windows.task_list_winid)
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

  -- Quick set in-progress with 'i'
  vim.keymap.set("n", "i", function()
    local task, _ = ui_module.get_task_at_cursor(task_lines_map, current_tasks, windows.task_list_winid)
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

  -- Toggle help with '?'
  vim.keymap.set("n", "?", function()
    ui_module.toggle_help()
    ui_module.refresh_task_list()
  end, opts)
end

return M
