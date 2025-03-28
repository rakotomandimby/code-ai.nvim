# Manage file exclusion more efficiently. 

`aiconfig.listScannedFilesFromConfig()` handle the inclusion and exclusion of files based on a configuration file.

I find its way to handle it to be the worst on earth because when `exclude_patterns` happens to have something such as `node_modules` or `dist` in it,
execution is very slow.

I want to change that, and first, I have put the `./lua/ai/globpattern.lua` to be an utility to handle the glob pattern.
Analyze the code of `./lua/ai/globpattern.lua` and laverage it to improve the performance of `aiconfig.listScannedFilesFromConfig()`.
I propose that we keep the current way to list files matching the `include_patterns` and then we filter out the files that match the `exclude_patterns` using the utility functions from `globpattern.lua`.

Propose a new implementation of `aiconfig.listScannedFilesFromConfig()` that uses the utility functions from `globpattern.lua` to handle the inclusion and exclusion of files more efficiently.



# This is gemini-2.5-pro-exp-03-25 answer (12k in, 2k out)

Okay, I understand the performance issue with the current `listScannedFilesFromConfig` function. Using `vim.fn.glob` for potentially large exclusion patterns like `node_modules/**` is indeed inefficient as it forces Neovim to traverse those directories.

Leveraging `lua/ai/globpattern.lua` to convert the exclusion globs into Lua patterns and then matching the included file paths against these patterns is a much better approach.

Here's the proposed updated content for `lua/ai/aiconfig.lua` incorporating this change:

```lua
-- Import the globpattern utility
local globpattern = require('ai.globpattern')
local aiconfig = {}

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


function aiconfig.listScannedFilesFromConfig()
  local config = aiconfig.findScannedFilesConfig()
  if config == "" then
    return {}
  end

  local include_patterns = {}
  local exclude_globs = {} -- Store original exclude globs

  -- Read the config file and separate include and exclude patterns
  for line in io.lines(config) do
    local trimmed_line = vim.trim(line)
    if vim.startswith(trimmed_line, "+") then
      table.insert(include_patterns, trimmed_line:sub(2)) -- Remove the '+' and add to include patterns
    elseif vim.startswith(trimmed_line, "-") then
      table.insert(exclude_globs, trimmed_line:sub(2)) -- Remove the '-' and add to exclude globs
    end
  end

  -- Step 1: Gather all files that match the include patterns using vim.fn.glob
  local included_files_set = {}
  for _, pattern in ipairs(include_patterns) do
    -- Use glob() which is generally efficient for finding files based on includes
    for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
      included_files_set[file] = true -- Use a table as a set to avoid duplicates
    end
  end

  -- Step 2: Convert exclude globs to Lua patterns using the globpattern utility
  local exclude_lua_patterns = {}
  for _, glob in ipairs(exclude_globs) do
    local lua_pattern = globpattern.globtopattern(glob)
    -- Only add valid patterns (globtopattern returns '[^]' on error)
    if lua_pattern ~= '[^]' then
      table.insert(exclude_lua_patterns, lua_pattern)
    else
      -- Optionally log or warn about invalid exclude patterns
      vim.notify("Warning: Invalid exclude glob pattern: " .. glob, vim.log.levels.WARN)
    end
  end

  -- Step 3: Filter the included files using the Lua patterns for exclusion
  local filtered_files = {}
  for file_path, _ in pairs(included_files_set) do
    local excluded = false
    for _, lua_pattern in ipairs(exclude_lua_patterns) do
      -- Use string.match to check if the file path matches an exclude pattern
      if string.match(file_path, lua_pattern) then
        excluded = true
        break -- No need to check other exclude patterns if one matches
      end
    end
    -- Only add the file if it was not excluded
    if not excluded then
      table.insert(filtered_files, file_path)
    end
  end

  -- Step 4: Create a list of the remaining files with their sizes
  local files_with_sizes = {}
  for _, file_path in ipairs(filtered_files) do
    local file_info = vim.loop.fs_stat(file_path)
    if file_info and file_info.type == 'file' then
      table.insert(files_with_sizes, {
        path = file_path,
        size = file_info.size
      })
    end
  end

  -- Step 5: Sort by file size (bigger to smaller)
  table.sort(files_with_sizes, function(a, b)
    return a.size > b.size
  end)

  -- Step 6: Extract just the file paths from the sorted list
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

**Summary of Changes in `aiconfig.listScannedFilesFromConfig()`:**

1.  **Import `globpattern`:** Added `local globpattern = require('ai.globpattern')` at the top.
2.  **Store Exclude Globs:** Renamed `exclude_patterns` to `exclude_globs` to clarify these are the original glob strings.
3.  **Gather Includes:** Kept the logic using `vim.fn.glob()` for `include_patterns` as this is generally efficient. Used a set (`included_files_set`) for deduplication.
4.  **Convert Exclude Globs to Lua Patterns:** Created a new table `exclude_lua_patterns`. Iterated through `exclude_globs`, converted each using `globpattern.globtopattern()`, and stored the resulting Lua pattern. Added a check for invalid patterns.
5.  **Filter Using Lua Patterns:** Iterated through the `included_files_set`. For each `file_path`, iterated through the `exclude_lua_patterns` and used `string.match()` to check for exclusion. This avoids calling `vim.fn.glob()` on exclude patterns. Built a new list `filtered_files` containing only the files that did *not* match any exclude pattern.
6.  **Sizing and Sorting:** Modified the sizing and sorting steps to operate on the `filtered_files` list instead of the potentially larger intermediate set.
7.  **Final List:** Extracted the paths from the sorted list into `final_files`.

This revised implementation should significantly improve performance when dealing with exclude patterns that match many files or directories.
