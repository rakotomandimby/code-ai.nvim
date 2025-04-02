# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints two lists of files in two tabble column.

- Values are accurate
- First column formatting is wrong: the right border of the first column is not aligned at all.
- Second column formatting is wrong: the right border of the second column is not aligned at all.

Lets change the code of `aiconfig.listScannedFilesAsFormattedTable()` to make a first pass loop dedicated to maximum file name length calculation, 
and a second pass loop to print the table.

Remove checking terminal size, because displaying that list is done inside a pop-up in a terminal application.

Propose me the changes to make to `aiconfig.listScannedFilesAsFormattedTable()` to make it print a beautiful table. 



# This is claude-3-7-sonnet-latest answer (15k in, 1k out)

# Improving `aiconfig.listScannedFilesAsFormattedTable()` Function

I'll rewrite the function to create a more beautiful, properly aligned table of scanned files. Here's the improved implementation:

```lua
-- Helper function to format file size
local function format_size(size)
  if size > 1024 * 1024 then
    return string.format("%.2f MB", size / (1024 * 1024))
  elseif size > 1024 then
    return string.format("%.2f KB", size / 1024)
  else
    return size .. " B"
  end
end

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

  -- First pass: gather data and calculate maximums for formatting
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

  -- Determine padding values for columns
  local size_col_width = math.max(#"Sorted by Size (Desc)", max_path_length + max_size_str_length + 3) -- +3 for " ()"
  local name_col_width = math.max(#"Sorted by Name (Asc)", max_path_length + max_size_str_length + 3) -- +3 for " ()"

  -- Build the Markdown table string
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. total_size_str .. " will be analyzed under project root " .. project_root .. ":\n")

  -- Define headers with padding
  local header1 = "Sorted by Size (Desc)"
  local header2 = "Sorted by Name (Asc)"
  table.insert(result_lines, "| " .. header1 .. string.rep(" ", size_col_width - #header1) .. " | " .. header2 .. string.rep(" ", name_col_width - #header2) .. " |")

  -- Define separator line with proper width
  table.insert(result_lines, "|" .. string.rep("-", size_col_width + 2) .. "|" .. string.rep("-", name_col_width + 2) .. "|")

  -- Helper function to format a file entry with consistent padding
  local function format_file_entry(path, size_str, col_width)
    local display = path .. " (" .. size_str .. ")"
    return display .. string.rep(" ", col_width - #display)
  end

  -- Add table rows
  for i = 1, #sorted_by_size do
    local item_size = sorted_by_size[i]
    local item_name = sorted_by_name[i]

    local display_size = format_file_entry(item_size.path, item_size.size_str, size_col_width)
    local display_name = format_file_entry(item_name.path, item_name.size_str, name_col_width)

    table.insert(result_lines, "| " .. display_size .. " | " .. display_name .. " |")
  end

  return table.concat(result_lines, "\n")
end
```

## Key Improvements:

1. **Better column alignment**: The new implementation calculates the exact width needed for each column based on the content's maximum length.

2. **Simplified approach**: Removed the terminal width checking and truncation logic, as you mentioned this is displayed in a popup anyway.

3. **Two-pass algorithm**:
   - First pass: Calculate maximum lengths and gather file data
   - Second pass: Format the table with proper padding

4. **Consistent padding**: Each column is padded to the same width throughout the table, creating clean vertical alignment.

5. **More readable code**: Separated the logic into smaller, more focused code blocks with clear responsibilities.

The new table will have perfectly aligned columns with all content visible, making it much easier to read and navigate.

