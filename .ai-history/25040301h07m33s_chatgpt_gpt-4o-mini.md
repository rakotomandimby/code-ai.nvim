# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints two lists of files in two tabble column.

- Values are accurate
- First column formatting is wrong: the right border of the first column is not aligned at all.
- Second column formatting is wrong: the right border of the second column is not aligned at all.

Lets change the code of `aiconfig.listScannedFilesAsFormattedTable()` to make a first pass loop dedicated to maximum file name length calculation, 
and a second pass loop to print the table.

Remove checking terminal size, because displaying that list is done inside a pop-up in a terminal application.

Propose me the changes to make to `aiconfig.listScannedFilesAsFormattedTable()` to make it print a beautiful table. 



# This is gpt-4o-mini answer (12k in, 0k out)

To enhance the `aiconfig.listScannedFilesAsFormattedTable()` function and ensure that it prints a well-aligned table, we will modify the function to include two passes: one for calculating the maximum lengths of the file names and sizes, and another for constructing the table output. We will also remove the terminal size checks since the output will be displayed in a pop-up.

Here’s the updated implementation of `aiconfig.listScannedFilesAsFormattedTable()`:

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
  local header1 = "File Path"
  local header2 = "Size"
  local header_line = "|" .. string.format(" %- " .. max_path_length .. "s | %- " .. max_size_str_length .. "s |", header1, header2) .. "|"
  local separator_line = "|" .. string.rep("-", max_path_length + 2) .. "|" .. string.rep("-", max_size_str_length + 2) .. "|"

  -- Build the Markdown table string
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. format_size(total_size) .. " will be analyzed under project root " .. project_root .. ":\n")
  table.insert(result_lines, header_line)
  table.insert(result_lines, separator_line)

  -- Add table rows
  for _, file_data in ipairs(files_data) do
    local display_path = string.format(" %- " .. max_path_length .. "s ", file_data.path)
    local display_size = string.format(" %- " .. max_size_str_length .. "s ", file_data.size_str)
    table.insert(result_lines, "|" .. display_path .. "| " .. display_size .. "|")
  end

  return table.concat(result_lines, "\n")
end
```

### Changes Made:
1. **Two Passes for Data Collection**: The first loop collects file data and calculates the maximum lengths for the file paths and size strings.
2. **Formatted Table Header**: A header line is created with proper formatting based on the maximum lengths calculated.
3. **Separator Line**: A separator line is added to visually separate the header from the data.
4. **Formatted Rows**: Each row is formatted to ensure that the file paths and sizes are aligned correctly.
5. **Removed Terminal Size Check**: The check for terminal size has been removed since the output will be displayed in a pop-up.

This implementation will ensure that the table is printed beautifully with aligned columns.

