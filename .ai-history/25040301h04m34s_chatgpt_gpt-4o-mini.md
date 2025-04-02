# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints two lists of files in two tabble column.

- Values are accurate
- First column formatting is wrong: the right border of the first column is not aligned at all.
- Second column formatting is wrong: the right border of the second column is not aligned at all.

Lets change the code of `aiconfig.listScannedFilesAsFormattedTable()` to make a first pass loop dedicated to maximum file name length calculation, 
and a second pass loop to print the table.

Propose me the changes to make to `aiconfig.listScannedFilesAsFormattedTable()` to make it print a beautiful table. 



# This is gpt-4o-mini answer (12k in, 0k out)

To improve the formatting of the table printed by `aiconfig.listScannedFilesAsFormattedTable()`, we will modify the function to first calculate the maximum lengths of the file names and their corresponding sizes. Then, we will use these lengths to format the output correctly in a second pass. Below is the updated implementation of the `listScannedFilesAsFormattedTable` function with comments explaining the changes.

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

  -- Create a header for the table
  local header1 = "Sorted by Size (Desc)"
  local header2 = "Sorted by Name (Asc)"
  
  -- Define maximum width for each column's content
  -- Get terminal width and calculate usable space
  local term_width = vim.o.columns
  local max_col_width = math.floor((term_width - 10) / 2) -- Subtract some space for borders and padding
  
  -- Cap the maximum length to prevent too wide columns
  max_path_length = math.min(max_path_length, max_col_width)
  max_size_str_length = math.min(max_size_str_length, max_col_width)

  -- Build the Markdown table string
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. format_size(total_size) .. " will be analyzed under project root " .. project_root .. ":\n")

  -- Define headers
  table.insert(result_lines, "| " .. header1 .. " | " .. header2 .. " |")
  -- Define separator line
  table.insert(result_lines, "|" .. string.rep("-", #header1 + 2) .. "|" .. string.rep("-", #header2 + 2) .. "|")

  -- Sort files_data by size descending
  table.sort(files_data, function(a, b) return a.size > b.size end)

  -- Add table rows for sorted by size
  for _, data in ipairs(files_data) do
    local display_path = string.format("%-*s", max_path_length, data.path) -- Left align path
    local display_size = string.format("%-*s", max_size_str_length, data.size_str) -- Left align size
    table.insert(result_lines, "| " .. display_path .. " | " .. display_size .. " |")
  end

  -- Sort files_data by name ascending
  table.sort(files_data, function(a, b) return a.path < b.path end)

  -- Add table rows for sorted by name
  for _, data in ipairs(files_data) do
    local display_path = string.format("%-*s", max_path_length, data.path) -- Left align path
    local display_size = string.format("%-*s", max_size_str_length, data.size_str) -- Left align size
    table.insert(result_lines, "| " .. display_path .. " | " .. display_size .. " |")
  end

  return table.concat(result_lines, "\n")
end
```

### Changes Made:
1. **First Pass Loop**: The first loop gathers file data and calculates the maximum lengths for both the file paths and their sizes.
2. **Second Pass Loop**: The second loop constructs the table rows using the calculated maximum lengths to ensure proper alignment.
3. **String Formatting**: Used `string.format` with `%-*s` to left-align the file paths and sizes based on the maximum lengths calculated.

This implementation will ensure that the table is printed beautifully with aligned columns.

