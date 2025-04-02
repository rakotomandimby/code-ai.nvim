# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints two lists of files in two tabble column.

- Values are accurate
- First column formatting is correct
- Second column formatting is wrong: the right border of the second column is not aligned at all.

I guess if the first column left and right borders are aligned, 
the maximum width of the content has been calculated somewhere 
so that the second column alignement could leverage it.

Propose a solution to fix the second column right border alignment.



# This is gemini-2.5-pro-exp-03-25 answer (14k in, 4k out)

Okay, I understand the issue. The second column's right border isn't aligned because its width isn't being calculated and used for padding, unlike the first column.

Here's the plan:

1.  Calculate the maximum width required for the second column, considering both its header and the longest file path string it will contain.
2.  Use this maximum width to pad the second column's header, separator, and content, just like it's done for the first column.

Let's modify the `lua/ai/aiconfig.lua` file.

```lua
-- lua/ai/aiconfig.lua
-- Add comments to indicate changes

local aiconfig = {}
local common = require("ai.common")
local globpattern = require("ai.globpattern")

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
  local project_root = aiconfig.getProjectRoot() -- Get project root once

  -- Iterate through include patterns
  for _, include_pattern in ipairs(include_glob_patterns) do
    common.log("Processing include glob pattern: " .. include_pattern)
    -- Use vim.fn.glob to find potential files matching the include pattern
    -- Ensure glob runs relative to the project root
    local potential_files = vim.fn.glob(project_root .. '/' .. include_pattern, false, true)

    for _, full_path in ipairs(potential_files) do
      -- Make path relative to project root for consistency and matching exclude patterns
      local relative_path = string.sub(full_path, #project_root + 2) -- +2 for the '/' and 1-based index

      -- Check if this file has already been added (to handle overlapping include patterns)
      if not processed_files[relative_path] then
        local is_excluded = false
        -- Check the relative path against each exclude Lua pattern
        for _, exclude_pattern in ipairs(exclude_lua_patterns) do
          if string.match(relative_path, exclude_pattern) then
            is_excluded = true
            common.log("File '" .. relative_path .. "' excluded by pattern: " .. exclude_pattern)
            break -- No need to check other exclude patterns for this file
          end
        end

        -- If the file is not excluded, get its stats and add it
        if not is_excluded then
          local file_info = vim.loop.fs_stat(full_path)
          -- Ensure it's a file (not a directory) before adding
          if file_info and file_info.type == 'file' then
            table.insert(files_with_sizes, {
              path = relative_path, -- Store relative path
              size = file_info.size
            })
            processed_files[relative_path] = true -- Mark as processed
            common.log("File '" .. relative_path .. "' included (Size: " .. file_info.size .. ")")
          else
             common.log("Path '" .. relative_path .. "' is not a file or stat failed, skipping.")
          end
        end
      else
        common.log("File '" .. relative_path .. "' already processed, skipping duplicate.")
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

function aiconfig.listScannedFilesAsSentence()
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
  -- Construct full path from project root and relative path
  local full_path = aiconfig.getProjectRoot() .. '/' .. file
  local f = io.open(full_path, "r")
  if f then
    local filecontent = f:read("*all")
    f:close()
    return filecontent
  end
  common.log("Could not read content of: " .. full_path)
  return ""
end

-- Helper function to format file size
local function format_size(size)
  if size > 1024 * 1024 then
    return string.format("%.2f MB", size / (1024 * 1024))
  elseif size > 1024 then
    return string.format("%.2f KB", size / 1024)
  else
    return size .. " B"
  end
end

--[[
  Generates a Markdown formatted table showing scanned files.
  The table has two columns:
  1. Files sorted by size (descending).
  2. Files sorted by name (ascending).
  Includes total size and project root information.
]]
function aiconfig.listScannedFilesAsFormattedTable()
  local analyzed_files_paths = aiconfig.listScannedFilesFromConfig()
  local project_root = aiconfig.getProjectRoot()

  if #analyzed_files_paths == 0 then
    return "# No files to analyze under project root " .. project_root
  end

  local files_data = {}
  local total_size = 0
  local max_width_col1 = 0 -- To store the max width for the first column content
  -- CHANGE: Initialize max width for the second column
  local max_width_col2 = 0

  -- Define headers early to include their length in width calculation
  local header1 = "Sorted by Size (Desc)"
  local header2 = "Sorted by Name (Asc)"
  -- CHANGE: Initialize max widths with header lengths
  max_width_col1 = #header1
  max_width_col2 = #header2

  -- Gather file data (path, size, formatted size) and calculate total size and max widths
  for _, relative_path in ipairs(analyzed_files_paths) do
    local full_path = project_root .. '/' .. relative_path
    local stat = vim.loop.fs_stat(full_path)
    local size = stat and stat.size or 0
    total_size = total_size + size
    local size_str = format_size(size)
    local display_str = relative_path .. " (" .. size_str .. ")"

    table.insert(files_data, {
      path = relative_path,
      size = size,
      size_str = size_str,
      display_str = display_str -- Pre-formatted string for display
    })

    -- Update max width needed for the first column
    if #display_str > max_width_col1 then
      max_width_col1 = #display_str
    end
    -- CHANGE: Update max width needed for the second column (using the same display string for now, as it's used in both columns)
    if #display_str > max_width_col2 then
      max_width_col2 = #display_str
    end
  end

  -- files_data is already sorted by size descending because analyzed_files_paths was
  local sorted_by_size = files_data

  -- Create a copy and sort it by name ascending
  local sorted_by_name = {}
  for _, data in ipairs(files_data) do
    table.insert(sorted_by_name, data)
  end
  table.sort(sorted_by_name, function(a, b)
    return a.path < b.path
  end)

  -- Format total size
  local total_size_str = format_size(total_size)

  -- Build the Markdown table string
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. total_size_str .. " will be analyzed under project root " .. project_root .. ":\n")

  -- Define headers, ensuring they are padded to the calculated max widths
  local padded_header1 = string.format("%-" .. max_width_col1 .. "s", header1)
  -- CHANGE: Pad the second header
  local padded_header2 = string.format("%-" .. max_width_col2 .. "s", header2)
  table.insert(result_lines, "| " .. padded_header1 .. " | " .. padded_header2 .. " |")

  -- Define separator line, matching the padding
  local separator1 = string.rep("-", max_width_col1)
  -- CHANGE: Create separator for the second column based on its max width
  local separator2 = string.rep("-", max_width_col2)
  table.insert(result_lines, "|-" .. separator1 .. "-|-" .. separator2 .. "-|")

  -- Add table rows
  -- CHANGE: Ensure we iterate up to the maximum number of rows needed (which is the total number of files)
  local num_rows = #files_data
  for i = 1, num_rows do
    -- CHANGE: Handle cases where one list might be shorter (though they should be the same length here)
    local item_size = sorted_by_size[i]
    local item_name = sorted_by_name[i]

    -- Pad the first column content to the max width
    local col1_content = item_size and item_size.display_str or "" -- Handle potential nil if lists differ in size
    local padded_col1_content = string.format("%-" .. max_width_col1 .. "s", col1_content)

    -- CHANGE: Pad the second column content to its max width
    local col2_content = item_name and item_name.display_str or "" -- Handle potential nil
    local padded_col2_content = string.format("%-" .. max_width_col2 .. "s", col2_content)

    table.insert(result_lines, "| " .. padded_col1_content .. " | " .. padded_col2_content .. " |")
  end

  return table.concat(result_lines, "\n")
end


return aiconfig
```

**Summary of Changes in `aiconfig.listScannedFilesAsFormattedTable()`:**

1.  **`max_width_col2` Initialization:** Added `max_width_col2` and initialized it (along with `max_width_col1`) with the length of the respective headers (`header2` and `header1`). This ensures the headers themselves are considered for column width.
2.  **`max_width_col2` Calculation:** Inside the loop that gathers file data, added a check to update `max_width_col2` if the current `display_str` is longer.
3.  **Header Padding:** Changed `padded_header2` to use `string.format` with `max_width_col2` for correct padding.
4.  **Separator Padding:** Changed `separator2` to use `string.rep("-", max_width_col2)` to match the calculated width.
5.  **Content Padding:** In the final loop that builds the table rows, added padding for the second column's content (`item_name.display_str`) using `string.format("%-" .. max_width_col2 .. "s", col2_content)`. Also added checks (`item_size and ... or ""`) just in case the lists could somehow end up with different lengths, although in the current logic they won't.

With these changes, the second column's content, header, and separator should all be padded correctly, resulting in an aligned right border for the Markdown table.
