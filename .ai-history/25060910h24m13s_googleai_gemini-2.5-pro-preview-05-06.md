# Append the content of `./lua/ai/common-system-instructions.md` to the user defined system common-system-instructions

In this plugin, I embeded a markdown file that contains the common system instructions that will be used by the AI to generate responses.
There instructions are to be hardcoded in the AI plugin and will not be changed by the user.
In `./lua/ai/aiconfig.lua`, I attempt to read the content of this file and append it to the user defined system instructions.
I fail to get the base path of the plugin in order to read the file.

 Give me the full new content of `./lua/ai/aiconfig.lua` to read the content of the plugin system instructions file and append it to the user defined system instructions.



# This is gemini-2.5-pro-preview-05-06 answer (17k in, 4k out)

# Append plugin's common system instructions

We will modify the `aiconfig.getSystemInstructions` function in `lua/ai/aiconfig.lua`.
The current implementation incorrectly tries to load the plugin's `common-system-instructions.md` file using a path relative to the current working directory.
We will change this to use `vim.api.nvim_get_runtime_file()` to correctly locate the file within the plugin's directory by searching Neovim's runtime path.

The updated function will:
1.  Attempt to read the user-defined system instructions from `.ai-system-instructions.md` in the project root.
2.  Attempt to read the plugin's built-in `common-system-instructions.md` file (expected to be at `lua/ai/common-system-instructions.md` relative to the plugin's root directory).
3.  Combine these instructions. If both exist, the user's instructions will appear first, followed by the plugin's common instructions. If only one set of instructions is found, that set will be used. If neither is found, an empty string will be returned.
4.  Add logging to trace the process of loading these instruction files.

Here is the full new content of `lua/ai/aiconfig.lua`:

```lua
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
  local user_instructions_path = aiconfig.findSystemInstructionsFile()
  local user_content = ""

  if user_instructions_path ~= "" then
    local file = io.open(user_instructions_path, "r")
    if file then
      user_content = file:read("*all")
      file:close()
      common.log("Read user system instructions from: " .. user_instructions_path)
    else
      -- This case means findSystemInstructionsFile found it, but io.open failed.
      -- This could be due to permissions or the file being deleted between checks.
      common.log("Error: Could not open user system instructions file: " .. user_instructions_path .. " (though it was detected).")
      -- user_content remains ""
    end
  else
    common.log("No user-defined system instructions file (.ai-system-instructions.md) found in project root: " .. vim.fn.getcwd())
    -- user_content remains ""
  end

  -- Now, get the plugin's common system instructions
  -- The file is expected to be at 'lua/ai/common-system-instructions.md' within the plugin's directory structure.
  local plugin_common_instruction_relative_path = "lua/ai/common-system-instructions.md"
  -- Search for the file in Neovim's runtimepath. `false` as the second argument means find the first occurrence.
  local runtime_paths = vim.api.nvim_get_runtime_file(plugin_common_instruction_relative_path, false)
  local plugin_common_instructions_full_path = ""

  if runtime_paths and #runtime_paths > 0 then
    plugin_common_instructions_full_path = runtime_paths[1] -- Take the first path found
    common.log("Found plugin's common system instructions file at: " .. plugin_common_instructions_full_path)
  else
    common.log("Error: Plugin's common system instructions file '" .. plugin_common_instruction_relative_path .. "' not found in Neovim's runtime path.")
  end

  local plugin_common_content = ""
  if plugin_common_instructions_full_path ~= "" then
    local common_file = io.open(plugin_common_instructions_full_path, "r")
    if common_file then
      plugin_common_content = common_file:read("*all")
      common_file:close()
      common.log("Successfully read plugin's common system instructions.")
    else
      common.log("Error: Could not open plugin's common system instructions file at: " .. plugin_common_instructions_full_path)
      -- plugin_common_content remains ""
    end
  end

  -- Combine the contents
  local final_content = user_content
  if plugin_common_content ~= "" then
    if final_content ~= "" then
      -- Ensure there's a clear separation if both exist
      final_content = final_content .. "\n\n" .. plugin_common_content
    else
      final_content = plugin_common_content
    end
  end

  if final_content == "" then
    common.log("No system instructions loaded (neither user-defined nor plugin's common instructions).")
  else
    common.log("Final system instructions assembled.")
  end

  return final_content
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

-- *** START: Modified listScannedFilesAsFormattedTable function ***
function aiconfig.listScannedFilesAsFormattedTable()
  local analyzed_files_paths = aiconfig.listScannedFilesFromConfig()
  local project_root = aiconfig.getProjectRoot()

  if #analyzed_files_paths == 0 then
    return "# No files to analyze under project root " .. project_root
  end

  local files_data = {}
  local total_size = 0
  local max_display_length = 0 -- Renamed: Tracks the max length of the combined "path (size)" string

  -- Pass 1: Gather data and calculate maximum display string length
  common.log("Starting Pass 1: Gathering file data and calculating max display length")
  for _, relative_path in ipairs(analyzed_files_paths) do
    local full_path = project_root .. '/' .. relative_path
    local stat = vim.loop.fs_stat(full_path)
    local size = stat and stat.size or 0
    total_size = total_size + size
    local size_str = format_size(size)
    -- Create the string that will actually be displayed in the table cell
    local display_str = relative_path .. " (" .. size_str .. ")"

    -- Track the maximum length needed for any cell content
    max_display_length = math.max(max_display_length, #display_str)

    table.insert(files_data, {
      path = relative_path,
      size = size,
      size_str = size_str,
      display_str = display_str -- Store the pre-formatted display string
    })
    common.log("Processed: " .. display_str .. " (Length: " .. #display_str .. ")")
  end
  common.log("Pass 1 Complete. Max display length: " .. max_display_length)

  -- files_data is already sorted by size descending because analyzed_files_paths was sorted by size
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

  -- Pass 2: Build the Markdown table string using calculated max length for padding
  common.log("Starting Pass 2: Building Markdown table")
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. total_size_str .. " will be analyzed under project root " .. project_root .. ":\n")

  -- Define headers
  local header1 = "Sorted by Size (Desc)"
  local header2 = "Sorted by Name (Asc)"

  -- Calculate column widths based on headers and max content length
  local col1_width = math.max(#header1, max_display_length)
  local col2_width = math.max(#header2, max_display_length)
  common.log("Calculated column widths: Col1=" .. col1_width .. ", Col2=" .. col2_width)

  -- Helper function for padding strings to a fixed width (left-aligned)
  local function pad_right(str, width)
    return str .. string.rep(" ", width - #str)
  end

  -- Add header row with padding
  table.insert(result_lines, "| " .. pad_right(header1, col1_width) .. " | " .. pad_right(header2, col2_width) .. " |")

  -- Add separator line based on calculated column widths
  table.insert(result_lines, "|-" .. string.rep("-", col1_width) .. "-|-" .. string.rep("-", col2_width) .. "-|") -- Use '-' for separators

  -- Add table rows with padding
  for i = 1, #sorted_by_size do
    -- Get the pre-calculated display strings
    local display_size = sorted_by_size[i].display_str
    local display_name = sorted_by_name[i].display_str

    -- Pad the display strings to the calculated column widths
    local padded_display_size = pad_right(display_size, col1_width)
    local padded_display_name = pad_right(display_name, col2_width)

    table.insert(result_lines, "| " .. padded_display_size .. " | " .. padded_display_name .. " |")
  end
  common.log("Pass 2 Complete. Table built.")

  return table.concat(result_lines, "\n")
end
-- *** END: Modified listScannedFilesAsFormattedTable function ***


return aiconfig
```
