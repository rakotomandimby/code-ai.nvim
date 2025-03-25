# Manage file inclusion and exclusion more efficiently. 

`aiconfig.listScannedFilesFromConfig()` handle the inclusion and exclusion of files based on a configuration file.

I find its way to handle it to be the worst on earth because when `exclude_patterns` happens to have something such as `node_modules` or `dist` in it,
execution is very slow.

Propose a better way to handle file inclusion and exclusion based on a configuration file.
Note that sorting the result on file size must be kept.



# This is gpt-4o-mini answer (9k in, 0k out)

To improve the efficiency of file inclusion and exclusion in the `aiconfig.listScannedFilesFromConfig()` function, we can utilize a more efficient approach by leveraging Lua's pattern matching capabilities and the `vim.fn.glob()` function. Instead of checking each file against all exclusion patterns after gathering all included files, we can directly filter out excluded files during the inclusion phase. This will significantly reduce the number of files processed and improve performance.

Here’s the updated implementation of `listScannedFilesFromConfig()`:

```lua
function aiconfig.listScannedFilesFromConfig()
  local config = aiconfig.findScannedFilesConfig()
  if config == "" then
    return {}
  end

  local include_patterns = {}
  local exclude_patterns = {}

  -- Read the config file and separate include and exclude patterns
  for line in io.lines(config) do
    local trimmed_line = vim.trim(line)
    if vim.startswith(trimmed_line, "+") then
      table.insert(include_patterns, trimmed_line:sub(2)) -- Remove the '+' and add to include patterns
    elseif vim.startswith(trimmed_line, "-") then
      table.insert(exclude_patterns, trimmed_line:sub(2)) -- Remove the '-' and add to exclude patterns
    end
  end

  -- Step 1: Gather all files that match the include patterns
  local included_files = {}
  for _, pattern in ipairs(include_patterns) do
    for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
      local is_excluded = false
      -- Check if the file matches any exclude patterns
      for _, exclude_pattern in ipairs(exclude_patterns) do
        if vim.fn.fnamemodify(file, ":t"):match(exclude_pattern) then
          is_excluded = true
          break
        end
      end
      if not is_excluded then
        included_files[file] = true -- Use a table to avoid duplicates
      end
    end
  end

  -- Step 2: Create a list of files with their sizes
  local files_with_sizes = {}
  for file, _ in pairs(included_files) do
    local file_info = vim.loop.fs_stat(file)
    if file_info and file_info.type == 'file' then
      table.insert(files_with_sizes, {
        path = file,
        size = file_info.size
      })
    end
  end

  -- Step 3: Sort by file size (bigger to smaller)
  table.sort(files_with_sizes, function(a, b)
    return a.size > b.size
  end)

  -- Step 4: Extract just the file paths from the sorted list
  local final_files = {}
  for _, file_data in ipairs(files_with_sizes) do
    table.insert(final_files, file_data.path)
  end

  return final_files
end
```

### Key Changes Made:
1. **Immediate Exclusion Check**: Instead of gathering all included files first and then checking for exclusions, we check for exclusions while we are gathering included files. This reduces the number of files processed significantly, especially when there are many excluded patterns.
  
2. **Pattern Matching**: The exclusion check uses `vim.fn.fnamemodify(file, ":t"):match(exclude_pattern)` to match the file name against the exclusion patterns. This allows for more flexible matching.

3. **Maintained Sorting**: The sorting of files by size is preserved, ensuring that the final output remains consistent with the original requirements.

### Benefits:
- **Performance Improvement**: This approach minimizes the number of files that need to be processed, especially in directories with many files, such as `node_modules` or `dist`.
- **Flexibility**: The use of pattern matching allows for more complex exclusion rules if needed in the future.

This implementation should provide a more efficient way to handle file inclusion and exclusion based on the configuration file.

