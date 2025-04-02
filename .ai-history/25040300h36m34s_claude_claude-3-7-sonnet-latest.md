# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints a list of files with their sizes between brackets.

This prints mostly like this:

```
# A total of 41.01 KB will be analyzed under project root /home/mihamina/Projects/RKTMB/rktmb-code-ai.nvim:
- lua/ai/init.lua (Size: 8.57 KB)
- lua/ai/aiconfig.lua (Size: 8.54 KB)
- lua/ai/gemini/query.lua (Size: 6.57 KB)
- lua/ai/chatgpt/query.lua (Size: 5.95 KB)
- lua/ai/anthropic/query.lua (Size: 5.18 KB)
- lua/ai/history.lua (Size: 2.59 KB)
- lua/ai/globpattern.lua (Size: 2.54 KB)
- lua/ai/common.lua (Size: 1.06 KB)
```

I want to change that to a better formatted table, with two columns:
- one column is the list of "files and their size", ordered by size, descending
- the other column is the list of files and their size, ordered by name, ascending

Propose me the modifications to apply to the `aiconfig.listScannedFilesAsFormattedTable()` function in order to achieve that.




# This is claude-3-7-sonnet-latest answer (14k in, 1k out)

# Implementing a Beautiful Table Display for Scanned Files

I'll modify the `aiconfig.listScannedFilesAsFormattedTable()` function to create a two-column table with files sorted by size and by name. Here's my implementation:

```lua
function aiconfig.listScannedFilesAsFormattedTable()
  local analyzed_files_as_array = aiconfig.listScannedFilesFromConfig()
  if #analyzed_files_as_array == 0 then
    return "# No files to analyze under project root " .. aiconfig.getProjectRoot()
  end

  -- Create a table of files with their sizes
  local files_with_sizes = {}
  local total_size = 0
  local max_filename_length = 0
  
  for _, file in ipairs(analyzed_files_as_array) do
    local stat = vim.loop.fs_stat(file)
    local size = stat and stat.size or 0
    total_size = total_size + size
    
    -- Get the max filename length for formatting
    max_filename_length = math.max(max_filename_length, #file)
    
    table.insert(files_with_sizes, {
      path = file,
      size = size,
      size_str = size <= 1024 and size .. " B" or
                 size <= 1024 * 1024 and string.format("%.2f KB", size / 1024) or
                 string.format("%.2f MB", size / (1024 * 1024))
    })
  end
  
  -- Format total size
  local total_size_str = total_size <= 1024 and total_size .. " B" or
                          total_size <= 1024 * 1024 and string.format("%.2f KB", total_size / 1024) or
                          string.format("%.2f MB", total_size / (1024 * 1024))
  
  -- Create a copy for sorting by name
  local files_by_name = {}
  for _, file_data in ipairs(files_with_sizes) do
    table.insert(files_by_name, vim.deepcopy(file_data))
  end
  
  -- Sort the lists
  table.sort(files_with_sizes, function(a, b)
    return a.size > b.size  -- Sort by size, descending
  end)
  
  table.sort(files_by_name, function(a, b)
    return a.path < b.path  -- Sort by path, ascending
  end)
  
  -- Create the markdown table
  local result = "# A total of " .. total_size_str .. " will be analyzed under project root " .. aiconfig.getProjectRoot() .. "\n\n"
  
  -- Calculate column width for better formatting
  local size_col_width = 12  -- "Size: XX.XX KB" - minimum width
  for _, file_data in ipairs(files_with_sizes) do
    size_col_width = math.max(size_col_width, #(file_data.size_str) + 6)  -- +6 for "Size: "
  end
  
  -- Create table header
  local header = "| Files by Size (Descending) " .. string.rep(" ", max_filename_length + size_col_width - 25) 
  header = header .. "| Files by Name (Ascending) " .. string.rep(" ", max_filename_length + size_col_width - 25) .. "|\n"
  
  local separator = "|" .. string.rep("-", max_filename_length + size_col_width) .. "|" 
  separator = separator .. string.rep("-", max_filename_length + size_col_width) .. "|\n"
  
  result = result .. header .. separator
  
  -- Fill the table rows
  local max_rows = math.max(#files_with_sizes, #files_by_name)
  for i = 1, max_rows do
    local row = "| "
    
    -- Files by size column
    if i <= #files_with_sizes then
      local file_data = files_with_sizes[i]
      row = row .. file_data.path .. " " .. string.rep(" ", max_filename_length - #file_data.path)
      row = row .. "(Size: " .. file_data.size_str .. ")" .. string.rep(" ", size_col_width - #file_data.size_str - 7)
    else
      row = row .. string.rep(" ", max_filename_length + size_col_width)
    end
    
    row = row .. "| "
    
    -- Files by name column
    if i <= #files_by_name then
      local file_data = files_by_name[i]
      row = row .. file_data.path .. " " .. string.rep(" ", max_filename_length - #file_data.path)
      row = row .. "(Size: " .. file_data.size_str .. ")" .. string.rep(" ", size_col_width - #file_data.size_str - 7)
    else
      row = row .. string.rep(" ", max_filename_length + size_col_width)
    end
    
    row = row .. "|\n"
    result = result .. row
  end
  
  return result
end
```

## Key Improvements

1. **Two-Column Table Format**: The function now generates a proper Markdown table with two columns.

2. **Better Size Formatting**: Sizes are consistently formatted (B, KB, MB) with the same precision.

3. **Dynamic Column Width**: The function calculates the maximum filename length and ensures consistent column widths.

4. **Dual Sorting**: 
   - Left column shows files sorted by size in descending order
   - Right column shows files sorted by name in ascending order

5. **Clean Header and Separator**: The table has a proper header and separator line following Markdown conventions.

This implementation creates a visually appealing table that will display well in the Neovim popup and maintains all the existing functionality while adding the requested visual improvements.

