# Manage file exclusion more efficiently. 

`aiconfig.listScannedFilesFromConfig()` handle the inclusion and exclusion of files based on a configuration file.

I find its way to handle it to be the worst on earth because when `exclude_patterns` happens to have something such as `node_modules` or `dist` in it,
execution is very slow.

I want to change that, and first, I have put the `./lua/ai/globpattern.lua` to be an utility to handle the glob pattern.
Analyze the code of `./lua/ai/globpattern.lua` and laverage it to improve the performance of `aiconfig.listScannedFilesFromConfig()`.
I propose that we check the matching of the filepath against the `exclude_patterns` before pushing it to the `included_files` list.
We should be able to get rid of the `excluded_files` list, because we already avoided pushing the excluded files to the `included_files` list.

Propose a new implementation of `aiconfig.listScannedFilesFromConfig()` that uses the utility functions from `globpattern.lua` to handle the inclusion and exclusion of files more efficiently.



# This is claude-3-7-sonnet-latest answer (12k in, 2k out)

# Improving File Scanning Efficiency in the AI Plugin

I'll help you improve the performance of the file scanning functionality by leveraging the `globpattern.lua` utility to optimize how we handle file exclusions, especially for large directories like `node_modules` or `dist`.

## Updated Implementation of `aiconfig.lua`

Here's my proposed implementation for the `listScannedFilesFromConfig()` function:

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

-- Improved implementation that leverages globpattern.lua
function aiconfig.listScannedFilesFromConfig()
  local config = aiconfig.findScannedFilesConfig()
  if config == "" then
    return {}
  end

  local include_patterns = {}
  local exclude_patterns = {}
  local exclude_pattern_regexes = {}

  -- Read the config file and separate include and exclude patterns
  for line in io.lines(config) do
    local trimmed_line = vim.trim(line)
    if vim.startswith(trimmed_line, "+") then
      table.insert(include_patterns, trimmed_line:sub(2)) -- Remove the '+' and add to include patterns
    elseif vim.startswith(trimmed_line, "-") then
      local pattern = trimmed_line:sub(2) -- Remove the '-'
      table.insert(exclude_patterns, pattern)
      -- Pre-convert glob pattern to Lua pattern
      table.insert(exclude_pattern_regexes, globpattern.globtopattern(pattern))
    end
  end

  -- Function to check if a file matches any exclude pattern
  local function is_excluded(file)
    for _, pattern in ipairs(exclude_pattern_regexes) do
      if file:match(pattern) then
        return true
      end
    end
    return false
  end

  -- Step 1: Gather all files that match the include patterns and aren't excluded
  local included_files = {}
  for _, pattern in ipairs(include_patterns) do
    for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
      if not is_excluded(file) and not included_files[file] then
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

1. **Pre-computed Pattern Matching**: 
   - We now pre-convert all exclude patterns to Lua regular expressions using `globpattern.globtopattern()` when they're first read from the config file.
   - This avoids repeated pattern conversion during file iteration.

2. **Early Exclusion Checking**:
   - Created an `is_excluded()` function that checks if a file matches any exclude pattern.
   - Files are checked against all exclusion patterns before being added to the included files list.

3. **Eliminated Double Processing**:
   - The previous implementation first collected all files, then separately removed excluded ones.
   - The new implementation checks exclusions during the initial collection phase.

4. **Reduced Memory Usage**:
   - By filtering files early, we avoid storing potentially large directories like `node_modules` in memory temporarily.

## Benefits of This Approach

1. **Performance Improvement**:
   - Large directories like `node_modules` or `dist` won't be temporarily stored in memory.
   - Early exclusion prevents unnecessary pattern matching on files we know we'll exclude later.

2. **More Direct Logic**:
   - The code is now more straightforward: collect included files that don't match exclusion patterns.
   - Removed the extra step of filtering out excluded files after initial collection.

3. **Reusable Pattern Conversion**:
   - By pre-converting glob patterns to Lua patterns, we do the conversion work once upfront rather than repeatedly.

This implementation should significantly improve performance when working with projects that have large directories to exclude, while maintaining the same functionality as the original implementation.

