local aiconfig = {}
local common = require("ai.common")
local globpattern = require("ai.globpattern")

function aiconfig.findSystemInstructionsFile()
  local path = vim.fn.getcwd() .. '/.ai-system-instructions.md'
  if vim.fn.filereadable(path) == 1 then
    return path
  else
    return ""
  end
end

-- Modified: Added append_embeded parameter to control system instructions appending
function aiconfig.getSystemInstructions(append_embeded)
  -- Default to true if not specified (preserve backward compatibility)
  if append_embeded == nil then
    append_embeded = true
  end

  local user_instructions_path = aiconfig.findSystemInstructionsFile()
  local content = ""
  if user_instructions_path ~= "" then
    local lines = vim.fn.readfile(user_instructions_path)
    if lines and #lines > 0 then
      content = table.concat(lines, "\n")
    else
      common.log("Could not read user system instructions or file is empty: " .. user_instructions_path)
    end
  end

  -- Only append embeded system instructions if append_embeded is true
  if not append_embeded then
    common.log("Skipping embeded system instructions due to configuration")
    return content
  end

  -- Find the common-system-instructions.md file in the plugin's runtime path
  local common_instructions_paths = vim.api.nvim_get_runtime_file("lua/ai/common-system-instructions_en.md", false)
  local common_content_found = false

  if #common_instructions_paths > 0 then
    local common_instructions_path = common_instructions_paths[1]
    common.log("Found common system instructions at: " .. common_instructions_path)
    if vim.fn.filereadable(common_instructions_path) == 1 then
      local common_lines = vim.fn.readfile(common_instructions_path)
      if common_lines and #common_lines > 0 then
        local common_content_str = table.concat(common_lines, "\n")
        if content ~= "" then
          content = content .. "\n\n" .. common_content_str
        else
          content = common_content_str
        end
        common_content_found = true
      else
        common.log("Could not read common system instructions or file is empty: " .. common_instructions_path)
      end
    else
      common.log("Common system instructions file not readable: " .. common_instructions_path)
    end
  else
    common.log("Common system instructions file not found in runtime paths via nvim_get_runtime_file.")
  end

  if not common_content_found then
    common.log("Common system instructions not found via runtime path, trying fallback.")
    -- As a fallback, try to find it relative to this file's location
    local current_file_info = debug.getinfo(1, "S")
    if current_file_info and current_file_info.source and current_file_info.source:sub(1,1) == "@" then
        local current_file_path = current_file_info.source:sub(2)
        local plugin_dir = vim.fn.fnamemodify(current_file_path, ":h:h") -- Assuming lua/ai/aiconfig.lua, so :h:h gives plugin root
        local fallback_path = plugin_dir .. "/lua/ai/common-system-instructions_en.md" -- Path relative to plugin root
        common.log("Trying fallback path: " .. fallback_path)
        if vim.fn.filereadable(fallback_path) == 1 then
          local fallback_lines = vim.fn.readfile(fallback_path)
          if fallback_lines and #fallback_lines > 0 then
            local common_content_str = table.concat(fallback_lines, "\n")
            if content ~= "" then
              content = content .. "\n\n" .. common_content_str
            else
              content = common_content_str
            end
          else
            common.log("Could not read common system instructions from fallback or file is empty: " .. fallback_path)
          end
        else
          common.log("Could not find common system instructions at fallback path (not readable): " .. fallback_path)
        end
    else
        common.log("Could not determine current file path for fallback common system instructions.")
    end
  end
  return content
end

function aiconfig.findScannedFilesConfig()
  local path = vim.fn.getcwd() .. '/.ai-scanned-files'
  if vim.fn.filereadable(path) == 1 then
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
  local config_path = aiconfig.findScannedFilesConfig()
  if config_path == "" then
    common.log("No .ai-scanned-files config found.")
    return {}
  end

  local include_glob_patterns = {}
  local exclude_glob_patterns = {}

  common.log("Reading scanned files config: " .. config_path)
  local lines = vim.fn.readfile(config_path)
  if not lines or #lines == 0 then
    common.log("Config file is empty or could not be read: " .. config_path)
    return {}
  end

  for _, line in ipairs(lines) do
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

  local exclude_lua_patterns = {}
  for _, pattern in ipairs(exclude_glob_patterns) do
    local lua_pattern = globpattern.globtopattern(pattern)
    table.insert(exclude_lua_patterns, lua_pattern)
    common.log("Converted exclude glob '" .. pattern .. "' to Lua pattern: " .. lua_pattern)
  end

  local files_with_sizes = {}
  local processed_files = {}
  local project_root = aiconfig.getProjectRoot()

  for _, include_pattern in ipairs(include_glob_patterns) do
    common.log("Processing include glob pattern: " .. include_pattern)
    local potential_files = vim.fn.glob(project_root .. '/' .. include_pattern, false, true)

    for _, full_path in ipairs(potential_files) do
      local relative_path = string.sub(full_path, #project_root + 2)

      if not processed_files[relative_path] then
        local is_excluded = false
        for _, exclude_pattern_lua in ipairs(exclude_lua_patterns) do
          if string.match(relative_path, exclude_pattern_lua) then
            is_excluded = true
            common.log("File '" .. relative_path .. "' excluded by pattern: " .. exclude_pattern_lua)
            break
          end
        end

        if not is_excluded then
          local file_info = vim.loop.fs_stat(full_path)
          if file_info and file_info.type == 'file' then
            table.insert(files_with_sizes, {
              path = relative_path,
              size = file_info.size
            })
            processed_files[relative_path] = true
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

  table.sort(files_with_sizes, function(a, b)
    return a.size > b.size
  end)

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

function aiconfig.contentOf(file_relative_path)
  local full_path = aiconfig.getProjectRoot() .. '/' .. file_relative_path
  if vim.fn.filereadable(full_path) == 1 then
    local lines = vim.fn.readfile(full_path)
    if lines then -- readfile returns empty list if file not found/readable, or list of lines
      return table.concat(lines, "\n")
    end
  end
  common.log("Could not read content of: " .. full_path)
  return ""
end

local function format_size(size)
  if size > 1024 * 1024 then
    return string.format("%.2f MB", size / (1024 * 1024))
  elseif size > 1024 then
    return string.format("%.2f KB", size / 1024)
  else
    return size .. " B"
  end
end

-- Count number of lines in a file. Returns 0 if not readable.
local function count_file_lines(full_path)
  if vim.fn.filereadable(full_path) ~= 1 then
    return 0
  end
  local lines = vim.fn.readfile(full_path)
  if not lines then
    return 0
  end
  return #lines
end

local function pad_right(str, width)
  if #str >= width then
    return str
  end
  return str .. string.rep(" ", width - #str)
end

local function pad_left(str, width)
  if #str >= width then
    return str
  end
  return string.rep(" ", width - #str) .. str
end

local function build_table(title, rows, total_lines, total_size_str)
  -- rows: array of { lines_str = "...", size_str = "...", percent_str = "...", name = "..." }
  local header_lines = "LoC"
  local header_size = "Size"
  local header_percent = "% size"
  local header_name = "File name"

  local col_lines_width = #header_lines
  local col_size_width = #header_size
  local col_percent_width = #header_percent
  local col_name_width = #header_name

  for _, row in ipairs(rows) do
    if #row.lines_str > col_lines_width then col_lines_width = #row.lines_str end
    if #row.size_str  > col_size_width  then col_size_width  = #row.size_str  end
    if #row.percent_str > col_percent_width then col_percent_width = #row.percent_str end
    if #row.name      > col_name_width  then col_name_width  = #row.name      end
  end

  -- Also account for the totals row
  local total_lines_str = tostring(total_lines)
  local total_label = "Total (" .. total_size_str .. ")"
  if #total_lines_str > col_lines_width then col_lines_width = #total_lines_str end
  if #total_label    > col_name_width  then col_name_width  = #total_label    end

  local out = {}
  table.insert(out, "## " .. title .. "\n")
  table.insert(out, "| " .. pad_right(header_lines, col_lines_width)
    .. " | " .. pad_right(header_size, col_size_width)
    .. " | " .. pad_right(header_percent, col_percent_width)
    .. " | " .. pad_right(header_name, col_name_width) .. " |")
  table.insert(out, "|-" .. string.rep("-", col_lines_width)
    .. "-|-" .. string.rep("-", col_size_width)
    .. "-|-" .. string.rep("-", col_percent_width)
    .. "-|-" .. string.rep("-", col_name_width) .. "-|")

  for _, row in ipairs(rows) do
    table.insert(out, "| " .. pad_left(row.lines_str, col_lines_width)
      .. " | " .. pad_left(row.size_str, col_size_width)
      .. " | " .. pad_left(row.percent_str, col_percent_width)
      .. " | " .. pad_right(row.name, col_name_width) .. " |")
  end


  return table.concat(out, "\n")
end

function aiconfig.listScannedFilesAsFormattedTable()
  local analyzed_files_paths = aiconfig.listScannedFilesFromConfig()
  local project_root = aiconfig.getProjectRoot()

  if #analyzed_files_paths == 0 then
    return "# No files to analyze under project root " .. project_root
  end

  local files_data = {}
  local total_size = 0
  local total_lines = 0

  common.log("Gathering file data for formatted table (size + line counts)")
  for _, relative_path in ipairs(analyzed_files_paths) do
    local full_path = project_root .. '/' .. relative_path
    local stat = vim.loop.fs_stat(full_path)
    local size = stat and stat.size or 0
    local nb_lines = count_file_lines(full_path)
    total_size = total_size + size
    total_lines = total_lines + nb_lines
    table.insert(files_data, {
      path = relative_path,
      size = size,
      size_str = format_size(size),
      nb_lines = nb_lines,
      nb_lines_str = tostring(nb_lines),
    })
    common.log("Processed: " .. relative_path .. " (Size: " .. size .. ", Lines: " .. nb_lines .. ")")
  end

  -- Calculate percent sizes
  for _, data in ipairs(files_data) do
    local percent = total_size > 0 and (data.size / total_size * 100) or 0
    data.percent_str = string.format("%.2f%%", percent)
  end

  local total_size_str = format_size(total_size)
  local num_files = #files_data

  -- Build sorted-by-size (desc) list - files_data is already sorted by size desc
  local rows_by_size = {}
  for _, data in ipairs(files_data) do
    table.insert(rows_by_size, {
      lines_str = data.nb_lines_str,
      size_str = data.size_str,
      percent_str = data.percent_str,
      name = data.path,
    })
  end

  -- Build sorted-by-name (asc) list
  local sorted_by_name = {}
  for _, data in ipairs(files_data) do
    table.insert(sorted_by_name, data)
  end
  table.sort(sorted_by_name, function(a, b) return a.path < b.path end)

  local rows_by_name = {}
  for _, data in ipairs(sorted_by_name) do
    table.insert(rows_by_name, {
      lines_str = data.nb_lines_str,
      size_str = data.size_str,
      percent_str = data.percent_str,
      name = data.path,
    })
  end

  local result_lines = {}
  table.insert(result_lines,
    "# Scanned files summary\n\n"
    .. "- Project root: `" .. project_root .. "`\n"
    .. "- Number of files: **" .. num_files .. "**\n"
    .. "- Total size: **" .. total_size_str .. "**\n"
    .. "- Total lines: **" .. total_lines .. "**\n")

  table.insert(result_lines, build_table("File list by size (descending)", rows_by_size, total_lines, total_size_str))
  table.insert(result_lines, "")
  table.insert(result_lines, build_table("File list by name (ascending)", rows_by_name, total_lines, total_size_str))

  return table.concat(result_lines, "\n")
end

return aiconfig

