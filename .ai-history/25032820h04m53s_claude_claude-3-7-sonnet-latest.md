# Manage file exclusion more efficiently. 

`aiconfig.listScannedFilesFromConfig()` handle the inclusion and exclusion of files based on a configuration file.

I find its way to handle it to be the worst on earth because when `exclude_patterns` happens to have something such as `node_modules` or `dist` in it,
execution is very slow.

I want to change that, and first, I have put the `./lua/ai/globpattern.lua` to be an utility to handle the glob pattern.
Analyze the code of `./lua/ai/globpattern.lua` and laverage it to improve the performance of `aiconfig.listScannedFilesFromConfig()`.
I propose that we keep the current way to list files matching the `include_patterns` and then we filter out the files that match the `exclude_patterns` using the utility functions from `globpattern.lua`.

Propose a new implementation of `aiconfig.listScannedFilesFromConfig()` that uses the utility functions from `globpattern.lua` to handle the inclusion and exclusion of files more efficiently.



# This is claude-3-7-sonnet-latest answer (12k in, 2k out)

# Improving File Exclusion Efficiency in `aiconfig.listScannedFilesFromConfig()`

The current implementation uses Vim's `glob()` function both for including and excluding files, which can be inefficient when excluding patterns like `node_modules` or `dist`. We can optimize this by using the `globpattern.lua` utility to convert glob patterns to Lua patterns and filter files in memory rather than making additional filesystem calls.

Here's a new implementation of `aiconfig.listScannedFilesFromConfig()`:

```lua
local aiconfig = {}
local globpattern = require('ai.globpattern')

function aiconfig.findSystemInstructionsFile()
  local path = vim.fn.getcwd() .. '/.ai-system-instructions.md'
  local file = io.open(path, "r")
  if file ~= nil then
    io.close(file)
    return path
  else
    return ""
  end
end

function aiconfig.getSystemInstructions()
  local path = aiconfig.findSystemInstructionsFile()
  if path == "" then
    return ""
  end

  local file = io.open(path, "r")
  if not file then
    return ""
  end

  local content = file:read("*all")
  file:close()
  return content
end

function aiconfig.findScannedFilesConfig()
  local path = vim.fn.getcwd() .. '/.ai-scanned-files'
  local file = io.open(path, "r")
  if file ~= nil then
    io.close(file)
    return path
  else
    return ""
  end
end

function aiconfig.getProjectRoot()
  -- To find the project root, we look upward for several files or directory, in this order:
  -- 1. The .ai-scanned-files file
  -- 2. The .git directory
  -- 3. The .gitignore file
  -- 4. The README.md file

  local project_root = vim.fn.getcwd() -- Start with the current working directory
  -- Check if the .ai-scanned-files file exists here or in any parent directory
  local configFile = aiconfig.findScannedFilesConfig()
  if configFile ~= "" then
    project_root = vim.fn.fnamemodify(configFile, ":h") -- Get the parent directory of the .ai-scanned-files file
    return project_root
  end

  -- Check if the .git directory exists here or in any parent directory
  local gitDir = vim.fn.finddir(".git", ".;") -- Find the .git directory
  if gitDir ~= "" then
    project_root = vim.fn.fnamemodify(gitDir, ":h") -- Get the parent directory of the .git directory
    return project_root
  end

  -- Check if the .gitignore file exists here or in any parent directory
  local gitignoreFile = vim.fn.findfile(".gitignore", ".;") -- Find the .gitignore file
  if gitignoreFile ~= "" then
    project_root = vim.fn.fnamemodify(gitignoreFile, ":h") -- Get the parent directory of the .gitignore file
    return project_root
  end

  -- Check if the README.md file exists here or in any parent directory
  local readmeFile = vim.fn.findfile("README.md", ".;") -- Find the README.md file
  if readmeFile ~= "" then
    project_root = vim.fn.fnamemodify(readmeFile, ":h") -- Get the parent directory of the README.md file
    return project_root
  end
  return project_root
end

-- New optimized implementation using globpattern
function aiconfig.listScannedFilesFromConfig()
  local config = aiconfig.findScannedFilesConfig()
  if config == "" then
    return {}
  end

  local include_patterns = {}
  local exclude_patterns = {}
  local lua_exclude_patterns = {} -- Will hold Lua patterns converted from glob patterns

  -- Read the config file and separate include and exclude patterns
  for line in io.lines(config) do
    local trimmed_line = vim.trim(line)
    if vim.startswith(trimmed_line, "+") then
      table.insert(include_patterns, trimmed_line:sub(2)) -- Remove the '+' and add to include patterns
    elseif vim.startswith(trimmed_line, "-") then
      -- Store original glob pattern
      table.insert(exclude_patterns, trimmed_line:sub(2))
      -- Convert to Lua pattern and store for later use
      table.insert(lua_exclude_patterns, globpattern.globtopattern(trimmed_line:sub(2)))
    end
  end

  -- Step 1: Gather all files that match the include patterns
  local included_files = {}
  for _, pattern in ipairs(include_patterns) do
    for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
      included_files[file] = true -- Use a table to avoid duplicates
    end
  end

  -- Step 2: Filter out files that match the exclude patterns using Lua patterns
  -- This avoids calling glob() again for exclusions
  local final_files = {}
  for file, _ in pairs(included_files) do
    local should_exclude = false
    for _, pattern in ipairs(lua_exclude_patterns) do
      if file:match(pattern) then
        should_exclude = true
        break
      end
    end
    
    if not should_exclude then
      table.insert(final_files, file)
    end
  end

  -- Step 3: Get file sizes for the remaining files
  local files_with_sizes = {}
  for _, file in ipairs(final_files) do
    local file_info = vim.loop.fs_stat(file)
    if file_info and file_info.type == 'file' then
      table.insert(files_with_sizes, {
        path = file,
        size = file_info.size
      })
    end
  end

  -- Step 4: Sort by file size (bigger to smaller)
  table.sort(files_with_sizes, function(a, b)
    return a.size > b.size
  end)

  -- Step 5: Extract just the file paths from the sorted list
  local result = {}
  for _, file_data in ipairs(files_with_sizes) do
    table.insert(result, file_data.path)
  end

  return result
end

function aiconfig.listScannedFilesAsText()
  local analyzed_files_as_array = aiconfig.listScannedFilesFromConfig()
  local num_files = #analyzed_files_as_array

  if num_files == 0 then
    return ""
  end

  local file_names = {}
  for _, file in ipairs(analyzed_files_as_array) do
    table.insert(file_names, string.format("`%%s`", file))
  end

  local analyzed_files_as_string = "The project is composed of " .. num_files .. " file" .. (num_files > 1 and "s" or "") .. ": "

  if num_files == 1 then
    analyzed_files_as_string = analyzed_files_as_string .. file_names[1] .. "."
  elseif num_files == 2 then
    analyzed_files_as_string = analyzed_files_as_string .. table.concat(file_names, " and ") .. "."
  else
    analyzed_files_as_string = analyzed_files_as_string .. table.concat(file_names, ", ", 1, num_files - 1) .. ", and " .. file_names[num_files] .. "."
  end

  return analyzed_files_as_string
end

function aiconfig.contentOf(file)
  local f = io.open(file, "r")
  if f then
    local filecontent = f:read("*all")
    f:close()
    return filecontent
  end
  return ""
end

function aiconfig.listScannedFiles()
  local analyzed_files_as_array = aiconfig.listScannedFilesFromConfig()
  if #analyzed_files_as_array == 0 then
    return "# No files to analyze under project root " .. aiconfig.getProjectRoot()
  end

  local analyzed_files_as_string = " will be analyzed under project root ".. aiconfig.getProjectRoot() .. ":\n"
  local total_size = 0 -- Initialize total size

  for _, file in ipairs(analyzed_files_as_array) do
    local stat = vim.loop.fs_stat(file)
    local size = stat and stat.size or 0 -- Default to 0 if size is unknown
    total_size = total_size + size -- Add file size to total

    local size_str = size .. " B"
    if size > 1024 then
      size_str = string.format("%.2f KB", size / 1024)
    end
    if size > 1024 * 1024 then
      size_str = string.format("%.2f MB", size / (1024 * 1024))
    end
    analyzed_files_as_string = analyzed_files_as_string .. "- " .. file .. " (Size: " .. size_str .. ")\n"
  end

  -- Format total size
  local total_size_str = total_size .. " B"
  if total_size > 1024 then
    total_size_str = string.format("%.2f KB", total_size / 1024)
  end
  if total_size > 1024 * 1024 then
    total_size_str = string.format("%.2f MB", total_size / (1024 * 1024))
  end

  -- Append total size to the string
  analyzed_files_as_string = "\n# A total of " .. total_size_str .. analyzed_files_as_string

  return analyzed_files_as_string
end

return aiconfig
```

## Key Improvements

1. **Efficient Exclusion**: Instead of using `vim.fn.glob()` for each exclusion pattern (which does filesystem traversal), we convert the glob patterns to Lua patterns using `globpattern.globtopattern()`.

2. **In-Memory Filtering**: After collecting all included files, we filter them in memory using Lua pattern matching, which is much faster than making additional filesystem calls.

3. **Single Pass Processing**: We process all files in a single pass through the filesystem rather than multiple passes.

4. **Readable Code**: The new implementation maintains the same logical flow but clearly separates the inclusion and exclusion steps.

This approach will be significantly faster when dealing with large exclude patterns like `node_modules` or `dist` because it avoids unnecessary filesystem traversals.

