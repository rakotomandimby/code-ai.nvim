# Manage file exclusion more efficiently. 

`aiconfig.listScannedFilesFromConfig()` handle the inclusion and exclusion of files based on a configuration file.

I find its way to handle it to be the worst on earth because when `exclude_patterns` happens to have something such as `node_modules` or `dist` in it,
execution is very slow.

I want to change that, and first, I have put the `./lua/ai/globpattern.lua` to be an utility to handle the glob pattern.
Analyze the code of `./lua/ai/globpattern.lua` and laverage it to improve the performance of `aiconfig.listScannedFilesFromConfig()`.
I propose that we check the matching of the filepath against the `exclude_patterns` before pushing it to the `included_files` list.
We should be able to get rid of the `excluded_files` list, because we already avoided pushing the excluded files to the `included_files` list.

Propose a new implementation of `aiconfig.listScannedFilesFromConfig()` that uses the utility functions from `globpattern.lua` to handle the inclusion and exclusion of files more efficiently.



# This is gemini-2.5-pro-exp-03-25 answer (12k in, 3k out)

Okay, I understand the performance issue with the current approach. Gathering all files matching include patterns first, especially broad ones like `**/*`, and *then* filtering out potentially large excluded sets like `node_modules/**` is indeed inefficient.

Using the `globpattern.lua` utility to convert exclusion globs into Lua patterns and checking each potential file *before* adding it to the list is a much better strategy.

Here's the proposed new implementation for `lua/ai/aiconfig.lua`, incorporating this change:

```lua
-- lua/ai/aiconfig.lua
local globpattern = require('ai.globpattern') -- Import the glob pattern utility
local common = require('ai.common') -- Import common utilities like logging

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


--[[
Improved function to list scanned files based on .ai-scanned-files config.
It now checks exclusion patterns *before* adding files to the list,
improving performance significantly for large exclusion sets.
]]
function aiconfig.listScannedFilesFromConfig()
  local config = aiconfig.findScannedFilesConfig()
  if config == "" then
    common.log("No .ai-scanned-files config found.")
    return {}
  end

  local include_glob_patterns = {}
  local exclude_glob_patterns = {}

  -- Read the config file and separate include and exclude glob patterns
  common.log("Reading scanned files config: " .. config)
  for line in io.lines(config) do
    local trimmed_line = vim.trim(line)
    if #trimmed_line > 1 then -- Ignore empty or single character lines
        if vim.startswith(trimmed_line, "+") then
          local pattern = trimmed_line:sub(2)
          table.insert(include_glob_patterns, pattern)
          common.log("Include glob pattern: " .. pattern)
        elseif vim.startswith(trimmed_line, "-") then
          local pattern = trimmed_line:sub(2)
          table.insert(exclude_glob_patterns, pattern)
          common.log("Exclude glob pattern: " .. pattern)
        end
    end
  end

  -- Convert exclude glob patterns to Lua regex patterns once
  local exclude_lua_patterns = {}
  for _, pattern in ipairs(exclude_glob_patterns) do
    local lua_pattern = globpattern.globtopattern(pattern)
    table.insert(exclude_lua_patterns, lua_pattern)
    common.log("Converted exclude glob '" .. pattern .. "' to Lua pattern: " .. lua_pattern)
  end

  local files_with_sizes = {}
  local processed_files = {} -- Use a set to avoid processing duplicates from overlapping include patterns

  -- Iterate through include patterns
  for _, include_pattern in ipairs(include_glob_patterns) do
    common.log("Processing include glob pattern: " .. include_pattern)
    -- Use vim.fn.glob to find potential files matching the include pattern
    -- Note: Assumes vim.fn.glob runs relative to the project root or patterns are adjusted accordingly.
    local potential_files = vim.fn.glob(include_pattern, false, true)

    for _, file in ipairs(potential_files) do
      -- Check if this file has already been added (to handle overlapping include patterns)
      if not processed_files[file] then
        local is_excluded = false
        -- Check the file against each exclude Lua pattern
        for _, exclude_pattern in ipairs(exclude_lua_patterns) do
          if string.match(file, exclude_pattern) then
            is_excluded = true
            common.log("File '" .. file .. "' excluded by pattern: " .. exclude_pattern)
            break -- No need to check other exclude patterns for this file
          end
        end

        -- If the file is not excluded, get its stats and add it
        if not is_excluded then
          local file_info = vim.loop.fs_stat(file)
          -- Ensure it's a file (not a directory) before adding
          if file_info and file_info.type == 'file' then
            table.insert(files_with_sizes, {
              path = file,
              size = file_info.size
            })
            processed_files[file] = true -- Mark as processed
            common.log("File '" .. file .. "' included (Size: " .. file_info.size .. ")")
          else
             common.log("Path '" .. file .. "' is not a file or stat failed, skipping.")
          end
        end
      else
        common.log("File '" .. file .. "' already processed, skipping duplicate.")
      end
    end
  end

  -- Sort the included files by size (descending)
  table.sort(files_with_sizes, function(a, b)
    return a.size > b.size
  end)

  -- Extract just the file paths from the sorted list
  local final_files = {}
  for _, file_data in ipairs(files_with_sizes) do
    table.insert(final_files, file_data.path)
  end

  common.log("Total included files after filtering and sorting: " .. #final_files)
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
    return "# No files to analyze under project root " .. aiconfig.getProjectRoot() .. " based on .ai-scanned-files"
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

**Summary of Changes:**

1.  **Require `globpattern`:** Added `local globpattern = require('ai.globpattern')` at the top.
2.  **Require `common`:** Added `local common = require('ai.common')` for logging.
3.  **Pre-compile Exclude Patterns:** The exclude glob patterns read from the config file are converted into Lua regex patterns using `globpattern.globtopattern()` *once* before processing any include patterns.
4.  **Iterate Includes, Filter Immediately:**
    *   The code iterates through each `include_pattern`.
    *   `vim.fn.glob()` finds potential files for that pattern.
    *   For *each* potential file, it checks against the pre-compiled `exclude_lua_patterns`.
    *   Only if a file does *not* match any exclude pattern is it considered for inclusion.
5.  **Duplicate Check:** A `processed_files` table (used as a set) is introduced to prevent adding the same file multiple times if it matches more than one include pattern.
6.  **Directly Build `files_with_sizes`:** Files passing the exclusion check and the file type check (`vim.loop.fs_stat`) are added directly to the `files_with_sizes` list. There's no intermediate `included_files` table holding potentially millions of entries anymore.
7.  **Logging:** Added `common.log` statements to help debug the file inclusion/exclusion process.
8.  **Removed Redundant Step:** The second loop that iterated through `exclude_patterns` to remove files is completely gone.

This revised approach should significantly speed up the process when dealing with broad include patterns and large, well-defined exclude patterns like `node_modules/**`, `dist/**`, or `build/**`.
