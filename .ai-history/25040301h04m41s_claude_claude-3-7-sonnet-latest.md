# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints two lists of files in two tabble column.

- Values are accurate
- First column formatting is wrong: the right border of the first column is not aligned at all.
- Second column formatting is wrong: the right border of the second column is not aligned at all.

Lets change the code of `aiconfig.listScannedFilesAsFormattedTable()` to make a first pass loop dedicated to maximum file name length calculation, 
and a second pass loop to print the table.

Propose me the changes to make to `aiconfig.listScannedFilesAsFormattedTable()` to make it print a beautiful table. 



# This is claude-3-7-sonnet-latest answer (14k in, 1k out)

# Improving `aiconfig.listScannedFilesAsFormattedTable()` 

I'll provide an improved implementation for the formatted table display that ensures proper alignment of columns. The key changes will be:

1. Calculate maximum lengths in a first pass
2. Create properly formatted rows with consistent padding
3. Use these calculated dimensions to create aligned table rows

Here's the revised implementation:

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
  
  -- First pass: gather file data and calculate total size
  for _, relative_path in ipairs(analyzed_files_paths) do
    local full_path = project_root .. '/' .. relative_path
    local stat = vim.loop.fs_stat(full_path)
    local size = stat and stat.size or 0
    total_size = total_size + size
    local size_str = format_size(size)

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

  -- Get terminal width for optimal display
  local term_width = vim.o.columns
  
  -- Second pass: calculate maximum column widths
  local max_path_length = 0
  local max_size_str_length = 0
  
  for _, file_data in ipairs(files_data) do
    max_path_length = math.max(max_path_length, #file_data.path)
    max_size_str_length = math.max(max_size_str_length, #file_data.size_str)
  end
  
  -- Calculate column width limits
  local available_width = term_width - 7 -- Account for borders and padding
  local max_col_width = math.floor(available_width / 2) -- Divide space evenly
  
  -- Cap maximum length to prevent too wide columns, but ensure size fits
  max_path_length = math.min(max_path_length, max_col_width - max_size_str_length - 4) -- Allow for size and padding
  
  -- Function to format entry with consistent width
  local function format_entry(path, size_str)
    -- Truncate path if needed
    local display_path = path
    if #path > max_path_length then
      local half = math.floor((max_path_length - 3) / 2)
      display_path = string.sub(path, 1, half) .. "..." .. string.sub(path, -half)
    end
    
    -- Calculate padding needed for alignment
    local entry = display_path .. " (" .. size_str .. ")"
    local padding = max_col_width - #entry
    padding = math.max(0, padding) -- Ensure padding is not negative
    
    return entry .. string.rep(" ", padding)
  end
  
  -- Build the Markdown table string
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. total_size_str .. " will be analyzed under project root " .. project_root .. ":\n")

  -- Define headers
  local header1 = "Sorted by Size (Desc)"
  local header2 = "Sorted by Name (Asc)"
  
  -- Calculate padding for headers to match column width
  local header1_padding = math.max(0, max_col_width - #header1)
  local header2_padding = math.max(0, max_col_width - #header2)
  
  local header1_padded = header1 .. string.rep(" ", header1_padding)
  local header2_padded = header2 .. string.rep(" ", header2_padding)
  
  table.insert(result_lines, "| " .. header1_padded .. " | " .. header2_padded .. " |")
  
  -- Separator line - matches exact column widths
  table.insert(result_lines, "|" .. string.rep("-", #header1_padded + 2) .. "|" .. string.rep("-", #header2_padded + 2) .. "|")

  -- Add table rows
  for i = 1, #sorted_by_size do
    local item_size = sorted_by_size[i]
    local item_name = sorted_by_name[i]

    local display_size = format_entry(item_size.path, item_size.size_str)
    local display_name = format_entry(item_name.path, item_name.size_str)

    table.insert(result_lines, "| " .. display_size .. " | " .. display_name .. " |")
  end

  return table.concat(result_lines, "\n")
end
```

The key improvements in this implementation:

1. We calculate maximum path and size string lengths in a first pass
2. We use these maximum lengths to calculate appropriate column widths based on terminal size
3. We properly pad table entries so columns align perfectly
4. We handle path truncation with ellipses when paths are too long
5. We ensure the headers and separator lines match the exact width of the content columns

This will produce a consistently aligned table with properly truncated paths when needed, making it much more readable while still showing all the important information.

