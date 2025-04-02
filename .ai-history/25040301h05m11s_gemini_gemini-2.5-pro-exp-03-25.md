# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints two lists of files in two tabble column.

- Values are accurate
- First column formatting is wrong: the right border of the first column is not aligned at all.
- Second column formatting is wrong: the right border of the second column is not aligned at all.

Lets change the code of `aiconfig.listScannedFilesAsFormattedTable()` to make a first pass loop dedicated to maximum file name length calculation, 
and a second pass loop to print the table.

Propose me the changes to make to `aiconfig.listScannedFilesAsFormattedTable()` to make it print a beautiful table. 



# This is gemini-2.5-pro-exp-03-25 answer (14k in, 4k out)

Okay, I understand the issue. The current table formatting doesn't correctly calculate the required width for each column *before* generating the rows, leading to misaligned borders, especially when path truncation occurs.

Let's refactor `aiconfig.listScannedFilesAsFormattedTable` to perform these steps:

1.  Gather all file data (path, size, formatted size).
2.  Sort the data by size (desc) and name (asc).
3.  **First Pass:** Iterate through the data to determine the *maximum displayed width* needed for each column, considering potential path truncation and the appended size string. Also, ensure the headers fit.
4.  **Second Pass:** Build the Markdown table string, using the calculated maximum widths to pad each cell correctly.

Here's the updated content for `lua/ai/aiconfig.lua`:

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
  Generates a Markdown table listing scanned files, sorted by size and name.

  This function performs the following steps:
  1. Retrieves the list of scanned file paths (already sorted by size).
  2. Gathers detailed data (path, size, formatted size) for each file.
  3. Creates a second list sorted by file path name.
  4. Calculates the maximum required width for each column by simulating
     the final display string (including truncated path and size) for every file.
  5. Builds the Markdown table string, padding each cell to the calculated
     maximum width for proper alignment.
]]
function aiconfig.listScannedFilesAsFormattedTable()
  local analyzed_files_paths = aiconfig.listScannedFilesFromConfig()
  local project_root = aiconfig.getProjectRoot()

  if #analyzed_files_paths == 0 then
    return "# No files to analyze under project root " .. project_root
  end

  -- Step 1 & 2: Gather data and create sorted lists
  local files_data = {}
  local total_size = 0

  for _, relative_path in ipairs(analyzed_files_paths) do
    local full_path = project_root .. '/' .. relative_path
    local stat = vim.loop.fs_stat(full_path)
    local size = stat and stat.size or 0
    total_size = total_size + size
    local size_str = format_size(size)

    table.insert(files_data, {
      path = relative_path,
      size = size,
      size_str = size_str
    })
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

  -- Step 3: Calculate maximum column widths (First Pass)
  local max_path_display_length = 60 -- Max characters for the path part before truncation
  local max_col1_width = 0
  local max_col2_width = 0

  -- Helper function to truncate path for display (returns only the path part)
  local function truncate_path_display(path)
    if #path > max_path_display_length then
      local half = math.floor((max_path_display_length - 3) / 2) -- -3 for "..."
      -- Ensure half is not negative if max_path_display_length is very small
      half = math.max(0, half)
      if half == 0 then return "..." end -- Handle extremely short max length
      return string.sub(path, 1, half) .. "..." .. string.sub(path, -half)
    else
      return path
    end
  end

  -- Helper function to get the full display string for a cell
  local function get_cell_display_string(item)
      local truncated_path = truncate_path_display(item.path)
      return truncated_path .. " (" .. item.size_str .. ")"
  end

  -- Iterate to find max widths
  for i = 1, #files_data do
    local item_size = sorted_by_size[i]
    local item_name = sorted_by_name[i]

    local display_str_col1 = get_cell_display_string(item_size)
    local display_str_col2 = get_cell_display_string(item_name)

    max_col1_width = math.max(max_col1_width, #display_str_col1)
    max_col2_width = math.max(max_col2_width, #display_str_col2)
  end

  -- Ensure headers fit
  local header1 = "Sorted by Size (Desc)"
  local header2 = "Sorted by Name (Asc)"
  max_col1_width = math.max(max_col1_width, #header1)
  max_col2_width = math.max(max_col2_width, #header2)

  -- Step 4: Build the Markdown table string (Second Pass)
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. total_size_str .. " will be analyzed under project root " .. project_root .. ":\n")

  -- Helper function to pad a string to a specific width
  local function pad_right(str, width)
    return str .. string.rep(" ", width - #str)
  end

  -- Add header row
  table.insert(result_lines, "| " .. pad_right(header1, max_col1_width) .. " | " .. pad_right(header2, max_col2_width) .. " |")

  -- Add separator line (using Markdown alignment syntax)
  table.insert(result_lines, "|:" .. string.rep("-", max_col1_width) .. "|:" .. string.rep("-", max_col2_width) .. "|")
  -- Alternative separator: "| " .. string.rep("-", max_col1_width) .. " | " .. string.rep("-", max_col2_width) .. " |"

  -- Add table rows
  for i = 1, #files_data do
    local item_size = sorted_by_size[i]
    local item_name = sorted_by_name[i]

    -- Generate the display strings again (could optimize by storing from first pass if needed)
    local display_col1 = get_cell_display_string(item_size)
    local display_col2 = get_cell_display_string(item_name)

    -- Pad the cell content
    local cell1 = pad_right(display_col1, max_col1_width)
    local cell2 = pad_right(display_col2, max_col2_width)

    table.insert(result_lines, "| " .. cell1 .. " | " .. cell2 .. " |")
  end

  return table.concat(result_lines, "\n")
end


return aiconfig
```

**Key Changes:**

1.  **Gather Data First:** The code now gathers all `files_data` (path, size, size_str) before proceeding.
2.  **Sorting:** Creates `sorted_by_size` (which `files_data` already is) and `sorted_by_name`.
3.  **`truncate_path_display` Helper:** A simplified helper function now *only* handles the path truncation logic.
4.  **`get_cell_display_string` Helper:** This new helper combines the (potentially truncated) path with the size string `(size_str)` to get the exact string that will be displayed in a cell.
5.  **First Pass for Width Calculation:**
    *   Iterates through the `files_data` index (`i`).
    *   For each `i`, it gets the corresponding item from `sorted_by_size` and `sorted_by_name`.
    *   It calls `get_cell_display_string` for both items to determine the *actual* string length that will be displayed in each column for that row.
    *   It updates `max_col1_width` and `max_col2_width` using `math.max`.
    *   It also ensures the column widths are at least as large as the headers.
6.  **`pad_right` Helper:** A simple helper function to add spaces to the right of a string to reach a target width.
7.  **Second Pass for Table Building:**
    *   Builds the header and separator lines using the calculated `max_col1_width` and `max_col2_width`. The separator line now uses Markdown's alignment syntax (`|:---|:---|`) for potentially better rendering in some viewers, though a simple dash separator also works.
    *   Iterates through the data again.
    *   Calls `get_cell_display_string` again to get the content for each cell.
    *   Uses `pad_right` to pad the cell content to the maximum width calculated in the first pass.
    *   Constructs the table row string with correctly padded cells.
8.  **Removed Terminal Width Logic:** The complex logic trying to adapt to terminal width was removed, simplifying the function and making the output consistent regardless of the terminal size. A fixed `max_path_display_length` is used for truncation instead.

This revised structure ensures that the padding applied in the final table generation step is based on the *actual maximum width* required by any cell in that column, resulting in a properly aligned Markdown table.
