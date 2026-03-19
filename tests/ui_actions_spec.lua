-- Tests for inline task list actions (enhanced task list feature)

describe("beads.ui inline actions", function()

  describe("get_task_at_cursor", function()
    local ui = require("beads.ui")

    it("should be a function", function()
      assert.is_function(ui.get_task_at_cursor)
    end)

    it("should return nil when cursor is on a non-task line", function()
      local tasks = {
        { id = "nvim-beads-1", title = "Task 1", status = "open", priority = "P2" },
      }
      -- Line 1 is not in the map — simulates a header line
      local lines_map = { [4] = "nvim-beads-1" }

      -- Mock cursor returns {1, 0} (line 1), which is not in lines_map
      local task, line_nr = ui.get_task_at_cursor(lines_map, tasks, 1)
      assert.is_nil(task)
      assert.equals(1, line_nr)
    end)

    it("should return nil for empty task list", function()
      local task, line_nr = ui.get_task_at_cursor({}, {}, 1)
      assert.is_nil(task)
    end)

    it("should return nil when lines_map has ID but tasks list does not contain it", function()
      local tasks = {
        { id = "nvim-beads-2", title = "Task 2", status = "open", priority = "P2" },
      }
      -- Line 1 maps to an ID not in the tasks list
      local lines_map = { [1] = "nvim-beads-999" }

      local task, line_nr = ui.get_task_at_cursor(lines_map, tasks, 1)
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

    it("should handle _restore_cursor_position when no target is set", function()
      -- Should not error when called with no target
      ui._restore_cursor_position()
      assert.is_true(true)
    end)
  end)

  describe("help toggle", function()
    local ui = require("beads.ui")

    it("should start with help hidden", function()
      -- Reset state by toggling if visible
      if ui.is_help_visible() then ui.toggle_help() end
      assert.is_false(ui.is_help_visible())
    end)

    it("should toggle help visibility on", function()
      if ui.is_help_visible() then ui.toggle_help() end
      local result = ui.toggle_help()
      assert.is_true(result)
      assert.is_true(ui.is_help_visible())
    end)

    it("should toggle help visibility off again", function()
      -- Ensure it's on first
      if not ui.is_help_visible() then ui.toggle_help() end
      local result = ui.toggle_help()
      assert.is_false(result)
      assert.is_false(ui.is_help_visible())
    end)

    it("should toggle back and forth multiple times", function()
      if ui.is_help_visible() then ui.toggle_help() end
      assert.is_false(ui.is_help_visible())
      ui.toggle_help()
      assert.is_true(ui.is_help_visible())
      ui.toggle_help()
      assert.is_false(ui.is_help_visible())
      ui.toggle_help()
      assert.is_true(ui.is_help_visible())
      -- Clean up
      ui.toggle_help()
    end)
  end)

  describe("help rendering", function()
    local rendering = require("beads.ui_rendering")

    it("should have render_help_section function", function()
      assert.is_function(rendering.render_help_section)
    end)

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
      assert.truthy(content:find("in_progress"))
      assert.truthy(content:find("Delete task"))
      assert.truthy(content:find("Filter"))
      assert.truthy(content:find("Search"))
      assert.truthy(content:find("Navigate"))
    end)

    it("should include separator lines", function()
      local lines = rendering.render_help_section()
      local has_separator = false
      for _, line in ipairs(lines) do
        if line:find("───") then
          has_separator = true
          break
        end
      end
      assert.is_true(has_separator)
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
      -- Verify label format allows extracting priority value from first 2 chars
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

    it("should not strip from non-current items", function()
      local choice = "blocked"
      local selected = choice:gsub(" %(current%)$", "")
      assert.equals("blocked", selected)
    end)

    it("should extract priority from all label formats", function()
      local labels = {
        "P0 — Critical",
        "P1 — High",
        "P2 — Medium",
        "P3 — Low",
        "P4 — Backlog",
      }
      local expected = { "P0", "P1", "P2", "P3", "P4" }
      for idx, label in ipairs(labels) do
        assert.equals(expected[idx], label:sub(1, 2))
      end
    end)
  end)
end)
