# Manage file inclusion and exclusion more efficiently. 

`aiconfig.listScannedFilesFromConfig()` handle the inclusion and exclusion of files based on a configuration file.

I find its way to handle it to be the worst on earth because when `exclude_patterns` happens to have something such as `node_modules` or `dist` in it,
execution is very slow.

Propose a better way to handle file inclusion and exclusion based on a configuration file.
Note that sorting the result on file size must be kept.



# This is gemini-2.5-pro-exp-03-25 answer (11k in, 3k out)

Okay, I understand the performance issue. Globbing large excluded directories like `node_modules/**` just to filter them out later is indeed inefficient.

We can optimize this by:

1.  Globbing only the `include` patterns.
2.  Separating `exclude` patterns into directory prefixes (like `node_modules/`) and general file patterns (like `*.log`).
3.  Iterating through the included files and efficiently checking them against the exclude prefixes (using string matching) and exclude patterns (using `vim.fn.glob2regpat` and `vim.fn.match`).

This avoids the expensive glob operation on potentially huge excluded directories.

Here's the proposed change to `lua/ai/aiconfig.lua`:

```lua
-- lua/ai/aiconfig.lua
local aiconfig = {}
local common = require('ai.common') -- Assuming common.lua is for logging or shared utilities

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


-- *** MODIFIED FUNCTION ***
-- More efficient handling of file inclusion and exclusion.
function aiconfig.listScannedFilesFromConfig()
  local config_file_path = aiconfig.findScannedFilesConfig()
  if config_file_path == "" then
    return {}
  end

  local project_root = aiconfig.getProjectRoot()
  -- Ensure project_root ends with a path separator for consistent prefix matching
  if not project_root:match("[/\\]$") then
      project_root = project_root .. '/'
  end

  local include_patterns = {}
  local exclude_dir_prefixes = {} -- Store directory prefixes for fast string matching
  local exclude_file_patterns = {} -- Store general glob patterns for regex matching

  -- Read the config file and separate patterns
  for line in io.lines(config_file_path) do
    local trimmed_line = vim.trim(line)
    if vim.startswith(trimmed_line, "+") then
      table.insert(include_patterns, trimmed_line:sub(2)) -- Remove '+'
    elseif vim.startswith(trimmed_line, "-") then
      local pattern = trimmed_line:sub(2) -- Remove '-'
      -- Check if it looks like a directory pattern (ends with / or /**)
      if pattern:match('/$') or pattern:match('/%*%*$') then
        -- Normalize the prefix: remove trailing /** or /
        local prefix = pattern:gsub('/%*%*$', '/'):gsub('/$', '/')
        -- Store the prefix relative to the project root
        table.insert(exclude_dir_prefixes, prefix)
      else
        -- Store general file patterns
        table.insert(exclude_file_patterns, pattern)
      end
    end
  end

  -- Step 1: Gather all unique files matching include patterns
  local included_files_set = {}
  for _, pattern in ipairs(include_patterns) do
    -- Use globpath to search relative to the project root
    -- Note: globpath might interpret patterns differently than simple glob, adjust if needed
    -- Using vim.fn.glob relative to project root might be more direct:
    local search_pattern = project_root .. pattern
    -- common.log("Globbing include pattern: " .. search_pattern) -- Optional logging
    -- Use {relative} = false (default) to get absolute paths
    for _, file in ipairs(vim.fn.glob(search_pattern, false, true)) do
        -- Ensure we have absolute paths for consistency
        local abs_file_path = vim.fn.fnamemodify(file, ':p')
        included_files_set[abs_file_path] = true -- Use a set to handle duplicates
    end
  end

  -- Step 2 & 3: Filter included files using exclude rules and gather sizes
  local files_with_sizes = {}
  for abs_file_path, _ in pairs(included_files_set) do
    local excluded = false
    local relative_path = string.sub(abs_file_path, #project_root + 1) -- Path relative to project root

    -- Check against directory prefixes (fast check)
    for _, prefix in ipairs(exclude_dir_prefixes) do
      if string.find(relative_path, prefix, 1, true) == 1 then -- Check if relative_path starts with prefix
        excluded = true
        -- common.log("Excluding (prefix match '".. prefix .."'): " .. relative_path) -- Optional logging
        break
      end
    end

    -- If not excluded by prefix, check against file patterns (slower check)
    if not excluded then
      for _, pattern in ipairs(exclude_file_patterns) do
        -- Convert glob pattern to Vim regex
        local vim_regex = vim.fn.glob2regpat(pattern)
        -- Match the regex against the relative path
        if vim.fn.match(relative_path, vim_regex) ~= -1 then
          excluded = true
          -- common.log("Excluding (pattern match '".. pattern .."'): " .. relative_path) -- Optional logging
          break
        end
      end
    end

    -- If not excluded, get size and add to list
    if not excluded then
      local file_info = vim.loop.fs_stat(abs_file_path)
      if file_info and file_info.type == 'file' then
        table.insert(files_with_sizes, {
          path = abs_file_path, -- Store absolute path
          size = file_info.size
        })
      -- else
        -- common.log("Skipping (not a file or stat failed): " .. abs_file_path) -- Optional logging
      end
    end
  end

  -- Step 4: Sort by file size (bigger to smaller)
  table.sort(files_with_sizes, function(a, b)
    return a.size > b.size
  end)

  -- Step 5: Extract just the file paths from the sorted list
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
  local project_root = aiconfig.getProjectRoot()
  -- Ensure project_root ends with a path separator
  if not project_root:match("[/\\]$") then
      project_root = project_root .. '/'
  end

  for _, file_path in ipairs(analyzed_files_as_array) do
    -- Make path relative for display
    local relative_path = string.sub(file_path, #project_root + 1)
    table.insert(file_names, string.format("`%s`", relative_path))
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
  local project_root = aiconfig.getProjectRoot() -- Get project root once

  if #analyzed_files_as_array == 0 then
    return "# No files to analyze under project root " .. project_root
  end

  -- Ensure project_root ends with a path separator
  if not project_root:match("[/\\]$") then
      project_root = project_root .. '/'
  end

  local analyzed_files_as_string = " will be analyzed under project root ".. project_root .. ":\n"
  local total_size = 0 -- Initialize total size

  for _, file_path in ipairs(analyzed_files_as_array) do
    local stat = vim.loop.fs_stat(file_path)
    local size = stat and stat.size or 0 -- Default to 0 if size is unknown
    total_size = total_size + size -- Add file size to total

    local size_str = size .. " B"
    if size > 1024 then
      size_str = string.format("%.2f KB", size / 1024)
    end
    if size > 1024 * 1024 then
      size_str = string.format("%.2f MB", size / (1024 * 1024))
    end
    -- Make path relative for display
    local relative_path = string.sub(file_path, #project_root + 1)
    analyzed_files_as_string = analyzed_files_as_string .. "- " .. relative_path .. " (Size: " .. size_str .. ")\n"
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

**Summary of Changes in `aiconfig.listScannedFilesFromConfig`:**

1.  **Get Project Root:** Determined early and used for relative path calculations. Ensured it ends with a path separator.
2.  **Separate Exclude Patterns:** Exclude patterns starting with `-` are now categorized:
    *   Patterns ending in `/` or `/**` are treated as directory prefixes (e.g., `node_modules/`). These are stored relative to the project root in `exclude_dir_prefixes`.
    *   Other patterns are treated as general file globs (e.g., `*.tmp`, `*_spec.lua`) and stored in `exclude_file_patterns`.
3.  **Include Globbing Only:** `vim.fn.glob` is now *only* called for the `include_patterns`. It searches relative to the project root and returns absolute paths. A set (`included_files_set`) is used to store unique absolute file paths.
4.  **Efficient Filtering:** The code iterates through the `included_files_set`:
    *   Calculates the path relative to the project root.
    *   **Directory Prefix Check:** It performs a fast `string.find` to see if the relative path *starts with* any of the `exclude_dir_prefixes`.
    *   **File Pattern Check:** If not excluded by a prefix, it converts each `exclude_file_pattern` into a Vim regular expression using `vim.fn.glob2regpat` and checks if the *relative path* matches using `vim.fn.match`.
5.  **Stat and Collect:** Only files that pass *both* exclusion checks have their stats retrieved using `vim.loop.fs_stat`.
6.  **Sort and Return:** The remaining steps (sorting by size, extracting paths) are the same.

**Changes in `listScannedFilesAsText` and `listScannedFiles`:**

*   These functions now also calculate the project root and convert the absolute paths returned by `listScannedFilesFromConfig` back to relative paths for display purposes, ensuring consistency.

This revised approach should significantly speed up the process when dealing with large excluded directories, as it avoids traversing them entirely during the exclusion phase.
