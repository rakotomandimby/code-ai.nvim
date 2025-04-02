# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints two lists of files in two tabble column.

But when I have long file names, it seems the code cant handle it.
On some projects, it prints the following error:

```
Error executing Lua callback: .../.local/share/nvim/lazy/code-ai.nvim/lua/ai/aiconfig.lua:291: invalid option '-115' to 'format'                                                                                                                                                                                                                                                           
```

Is it really a problem of file name being too long?



# This is gpt-4o-mini answer (12k in, 0k out)

Yes, the error you're encountering is likely due to the formatting of the table when the file names are too long. The `string.format` function in Lua has limitations on the width of the fields it can handle, and if the file names exceed the specified width, it can lead to errors like the one you are seeing.

To address this issue, we can modify the `aiconfig.listScannedFilesAsFormattedTable()` function to ensure that the table is printed in a more flexible way, accommodating longer file names without causing formatting errors. 

Here’s an updated version of the `aiconfig.lua` file with the necessary changes:

```lua
function aiconfig.listScannedFilesAsFormattedTable()
  local analyzed_files_paths = aiconfig.listScannedFilesFromConfig()
  local project_root = aiconfig.getProjectRoot()

  if #analyzed_files_paths == 0 then
    return "# No files to analyze under project root " .. project_root
  end

  local files_data = {}
  local total_size = 0

  -- Gather file data (path, size, formatted size) and calculate total size
  for _, relative_path in ipairs(analyzed_files_paths) do
    local full_path = project_root .. '/' .. relative_path
    local stat = vim.loop.fs_stat(full_path)
    local size = stat and stat.size or 0
    total_size = total_size + size
    local size_str = format_size(size)

    table.insert(files_data, {
      path = relative_path,
      size = size,
      size_str = size_str,
    })
  end

  -- Sort files_data by size descending
  table.sort(files_data, function(a, b)
    return a.size > b.size
  end)

  -- Format total size
  local total_size_str = format_size(total_size)

  -- Build the Markdown table string
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. total_size_str .. " will be analyzed under project root " .. project_root .. ":\n")

  -- Define headers
  local header1 = "File Path"
  local header2 = "Size"
  local max_width_col1 = 0
  local max_width_col2 = 0

  -- Calculate max widths for columns
  for _, file_data in ipairs(files_data) do
    if #file_data.path > max_width_col1 then
      max_width_col1 = #file_data.path
    end
    if #file_data.size_str > max_width_col2 then
      max_width_col2 = #file_data.size_str
    end
  end

  -- Add headers to result
  table.insert(result_lines, string.format("| %-" .. max_width_col1 .. "s | %-" .. max_width_col2 .. "s |", header1, header2))
  table.insert(result_lines, string.rep("-", max_width_col1 + max_width_col2 + 7)) -- +7 for the pipe and spaces

  -- Add table rows
  for _, file_data in ipairs(files_data) do
    table.insert(result_lines, string.format("| %-" .. max_width_col1 .. "s | %-" .. max_width_col2 .. "s |", file_data.path, file_data.size_str))
  end

  return table.concat(result_lines, "\n")
end
```

### Changes Made:
1. **Dynamic Column Width Calculation**: The code now calculates the maximum width for each column based on the longest file name and size string. This ensures that the table can accommodate longer file names without causing formatting errors.
  
2. **Flexible Formatting**: The `string.format` function is used with dynamic widths, allowing for proper alignment of the table even with varying lengths of file names.

3. **Improved Header and Separator Handling**: The header and separator lines are adjusted to match the calculated widths, ensuring a clean and visually appealing table format.

With these changes, the function should now handle long file names gracefully and avoid the formatting errors you were experiencing.

