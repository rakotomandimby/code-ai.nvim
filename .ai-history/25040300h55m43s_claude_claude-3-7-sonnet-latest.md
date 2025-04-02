# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints two lists of files in two tabble column.

But when I have long file names, it seems the code cant handle it.
On some projects, it prints the following error:

```
Error executing Lua callback: .../.local/share/nvim/lazy/code-ai.nvim/lua/ai/aiconfig.lua:291: invalid option '-115' to 'format'                                                                                                                                                                                                                                                           
```

Is it really a problem of file name being too long?



# This is claude-3-7-sonnet-latest answer (15k in, 1k out)

# Fix for `aiconfig.listScannedFilesAsFormattedTable()` Function

After analyzing the code, I found that the error occurs when trying to format strings using negative width values in `string.format()`. This happens because the code doesn't properly handle cases where display strings (filenames with sizes) are longer than the terminal width.

Here's my implementation of a fixed version of `aiconfig.listScannedFilesAsFormattedTable()`:

```lua
function aiconfig.listScannedFilesAsFormattedTable()
  local analyzed_files_paths = aiconfig.listScannedFilesFromConfig()
  local project_root = aiconfig.getProjectRoot()

  if #analyzed_files_paths == 0 then
    return "# No files to analyze under project root " .. project_root
  end

  local files_data = {}
  local total_size = 0
  local max_path_length = 0
  local max_size_str_length = 0

  -- Gather file data (path, size, formatted size) and calculate total size
  for _, relative_path in ipairs(analyzed_files_paths) do
    local full_path = project_root .. '/' .. relative_path
    local stat = vim.loop.fs_stat(full_path)
    local size = stat and stat.size or 0
    total_size = total_size + size
    local size_str = format_size(size)

    -- Track maximum lengths for formatting
    max_path_length = math.max(max_path_length, #relative_path)
    max_size_str_length = math.max(max_size_str_length, #size_str)

    table.insert(files_data, {
      path = relative_path,
      size = size,
      size_str = size_str
    })
  end

  -- files_data is already sorted by size descending because analyzed_files_paths was
  local sorted_by_size = files_data

  -- Create a copy and sort it by name ascending
  local sorted_by_name = {}
  for _, data in ipairs(files_data) do
    table.insert(sorted_by_name, data)
  end
  table.sort(sorted_by_name, function(a, b)
    return a.path < b.path
  end)

  -- Format total size
  local total_size_str = format_size(total_size)

  -- Define maximum width for each column's content
  -- Get terminal width and calculate usable space
  local term_width = vim.o.columns
  local max_col_width = math.floor((term_width - 10) / 2) -- Subtract some space for borders and padding
  
  -- Cap the maximum length to prevent too wide columns
  max_path_length = math.min(max_path_length, max_col_width)

  -- Build the Markdown table string
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. total_size_str .. " will be analyzed under project root " .. project_root .. ":\n")

  -- Define headers
  local header1 = "Sorted by Size (Desc)"
  local header2 = "Sorted by Name (Asc)"
  table.insert(result_lines, "| " .. header1 .. " | " .. header2 .. " |")

  -- Define separator line
  table.insert(result_lines, "|" .. string.rep("-", #header1 + 2) .. "|" .. string.rep("-", #header2 + 2) .. "|")

  -- Helper function to truncate and format path display
  local function format_path_display(path, size_str)
    local display = path
    if #path > max_path_length then
      local half = math.floor((max_path_length - 3) / 2)
      display = string.sub(path, 1, half) .. "..." .. string.sub(path, -half)
    end
    return display .. " (" .. size_str .. ")"
  end

  -- Add table rows
  for i = 1, #sorted_by_size do
    local item_size = sorted_by_size[i]
    local item_name = sorted_by_name[i]

    local display_size = format_path_display(item_size.path, item_size.size_str)
    local display_name = format_path_display(item_name.path, item_name.size_str)

    table.insert(result_lines, "| " .. display_size .. " | " .. display_name .. " |")
  end

  return table.concat(result_lines, "\n")
end
```

## What Changed?

1. **Removed problematic string.format()**:
   - The original code used `string.format("%-" .. max_width .. "s", text)` which would fail if max_width was very large
   - I replaced this with a simpler approach that doesn't rely on negative format widths

2. **Added path truncation**:
   - Added a `format_path_display` function that truncates long paths with ellipses
   - This prevents table columns from becoming too wide for the terminal

3. **Terminal-aware widths**:
   - Now considers the terminal width (`vim.o.columns`) when formatting
   - Limits column widths to a reasonable portion of the terminal

4. **Simplified table formatting**:
   - Removed the padding calculation that could lead to errors
   - Used simpler, more robust table rendering that works reliably with any length strings

This implementation should fix the `invalid option to 'format'` error and make the table display correctly even with very long filenames.

