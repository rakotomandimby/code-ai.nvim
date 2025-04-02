# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints two lists of files in two tabble column.

But when I have long file names, it seems the code cant handle it.
On some projects, it prints the following error:

```
Error executing Lua callback: .../.local/share/nvim/lazy/code-ai.nvim/lua/ai/aiconfig.lua:291: invalid option '-115' to 'format'                                                                                                                                                                                                                                                           
```

Is it really a problem of file name being too long?



# This is gemini-2.5-pro-exp-03-25 answer (14k in, 4k out)

Okay, let's look at the `aiconfig.listScannedFilesAsFormattedTable` function and the error you're encountering.

You are right to suspect the width calculation, although the error `invalid option '-115' to 'format'` is quite peculiar. `string.format("%-" .. width .. "s", text)` expects `width` to be a non-negative integer. The code calculates `max_width_col1` and `max_width_col2` based on the lengths of the `display_str` (`relative_path .. " (" .. size_str .. ")"`), which should always result in non-negative lengths. It's very strange that it would end up being `-115`.

However, there *is* a definite bug in the current width calculation logic that *will* cause formatting issues, especially with long file names or when the headers are longer than the file names:

**The Bug:** The code calculates the maximum width needed for each column based *only* on the file data (`display_str`). It completely ignores the length of the column headers (`"Sorted by Size (Desc)"` and `"Sorted by Name (Asc)"`). If a header is longer than any file entry in that column, the calculated `max_width_colX` will be too small, causing the table columns to misalign.

**The Fix:** We need to ensure the calculated width for each column is the maximum of the longest data entry *and* the header length for that column.

While this fix directly addresses the alignment problem, it *might* also resolve the `-115` error, perhaps if the error reporting was slightly off or if the incorrect width calculation was somehow leading to an unexpected state later. If the error persists after this fix, we'd need to add more debugging (like printing the `max_width_colX` values just before the `string.format` call) to pinpoint the source of the negative number.

Let's apply the fix to ensure the column widths account for the headers.

```lua
-- lua/ai/aiconfig.lua
-- Provide the full file content
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
          -- Handle potential nil relative_path just in case
          if relative_path and string.match(relative_path, exclude_pattern) then
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
             common.log("Path '" .. (relative_path or "nil") .. "' is not a file or stat failed, skipping.")
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

function aiconfig.listScannedFilesAsFormattedTable()
  local analyzed_files_paths = aiconfig.listScannedFilesFromConfig()
  local project_root = aiconfig.getProjectRoot()

  if #analyzed_files_paths == 0 then
    return "# No files to analyze under project root " .. project_root
  end

  local files_data = {}
  local total_size = 0
  local max_width_col1_data = 0 -- Max width for the *data* in column 1
  local max_width_col2_data = 0 -- Max width for the *data* in column 2

  -- Gather file data (path, size, formatted size) and calculate total size and max data widths
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

    -- Update max width needed for the data in the first column
    if #display_str > max_width_col1_data then
      max_width_col1_data = #display_str
    end

    -- Update max width needed for the data in the second column (same display format)
    if #display_str > max_width_col2_data then
      max_width_col2_data = #display_str
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

  -- Define headers
  local header1 = "Sorted by Size (Desc)"
  local header2 = "Sorted by Name (Asc)"

  -- *** FIX START ***
  -- Calculate the final column width by taking the maximum of the data width and the header width
  local final_width_col1 = math.max(max_width_col1_data, #header1)
  local final_width_col2 = math.max(max_width_col2_data, #header2)
  -- *** FIX END ***

  -- Pad headers using the final calculated widths
  local padded_header1 = string.format("%-" .. final_width_col1 .. "s", header1)
  local padded_header2 = string.format("%-" .. final_width_col2 .. "s", header2)
  table.insert(result_lines, "| " .. padded_header1 .. " | " .. padded_header2 .. " |")

  -- Define separator line using the final calculated widths
  local separator1 = string.rep("-", final_width_col1)
  local separator2 = string.rep("-", final_width_col2)
  table.insert(result_lines, "|-" .. separator1 .. "-|-" .. separator2 .. "-|")

  -- Add table rows, ensuring we don't go out of bounds if lists differ (shouldn't happen here, but good practice)
  local max_rows = math.max(#sorted_by_size, #sorted_by_name)
  for i = 1, max_rows do
    local item_size = sorted_by_size[i]
    local item_name = sorted_by_name[i]

    -- Get display strings, handling potential nil if lists were uneven
    local display_col1 = item_size and item_size.display_str or ""
    local display_col2 = item_name and item_name.display_str or ""

    -- Pad the column content using the final calculated widths
    local padded_col1_content = string.format("%-" .. final_width_col1 .. "s", display_col1)
    local padded_col2_content = string.format("%-" .. final_width_col2 .. "s", display_col2)

    table.insert(result_lines, "| " .. padded_col1_content .. " | " .. padded_col2_content .. " |")
  end

  return table.concat(result_lines, "\n")
end


return aiconfig
```

**Explanation of Changes:**

1.  **Renamed Width Variables:** Renamed `max_width_col1` to `max_width_col1_data` and `max_width_col2` to `max_width_col2_data` to clarify that these initially hold the maximum width required *only by the data*.
2.  **Calculate Final Widths:** After gathering all file data and calculating the maximum *data* widths (`max_width_col1_data`, `max_width_col2_data`), we now calculate the `final_width_col1` and `final_width_col2`. This is done using `math.max` to compare the data width with the length of the corresponding header string (`#header1`, `#header2`).
3.  **Use Final Widths:** All subsequent `string.format` calls (for headers and data rows) and `string.rep` calls (for the separator line) now use these `final_width_col1` and `final_width_col2`. This ensures that the columns are wide enough to accommodate both the longest data entry *and* the header, resulting in a correctly aligned Markdown table.
4.  **Safer Loop for Rows:** Changed the loop limit from `#sorted_by_size` to `math.max(#sorted_by_size, #sorted_by_name)` and added checks for `nil` when accessing `item_size` and `item_name`. While `sorted_by_size` and `sorted_by_name` *should* always have the same length in the current logic, this makes the code slightly more robust against potential future changes.

Try this updated version. It should produce a correctly formatted table regardless of file name or header lengths. Please let me know if the peculiar `-115` error persists even with this corrected logic.
