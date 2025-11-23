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
  local common_instructions_paths = vim.api.nvim_get_runtime_file("lua/ai/common-system-instructions.md", false)
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
        local fallback_path = plugin_dir .. "/lua/ai/common-system-instructions.md" -- Path relative to plugin root
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

local function format_percentage(part, total)
  if total <= 0 then
    return "0%"
  end
  local percentage = (part / total) * 100
  if percentage >= 10 then
    return string.format("%.1f%%", percentage)
  else
    return string.format("%.2f%%", percentage)
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
  local max_display_length_size = 0
  local max_display_length_name = 0

  common.log("Starting Pass 1: Gathering file data and calculating max display length")
  for _, relative_path in ipairs(analyzed_files_paths) do
    local full_path = project_root .. '/' .. relative_path
    local stat = vim.loop.fs_stat(full_path)
    local size = stat and stat.size or 0
    total_size = total_size + size
    local size_str = format_size(size)
    local name_display_str = relative_path .. " (" .. size_str .. ")"
    max_display_length_name = math.max(max_display_length_name, #name_display_str)
    table.insert(files_data, {
      path = relative_path,
      size = size,
      size_str = size_str,
      display_name = name_display_str
    })
    common.log("Processed: " .. name_display_str .. " (Length: " .. #name_display_str .. ")")
  end
  common.log("Pass 1 Complete. Max display length (name): " .. max_display_length_name)

  local total_size_str = format_size(total_size)

  for _, data in ipairs(files_data) do
    local percentage_str = format_percentage(data.size, total_size)
    data.display_size = data.path .. " (" .. data.size_str .. ", " .. percentage_str .. ")"
    max_display_length_size = math.max(max_display_length_size, #data.display_size)
  end
  common.log("Computed percentage contributions for all files.")

  local sorted_by_size = files_data

  local sorted_by_name = {}
  for _, data in ipairs(files_data) do
    table.insert(sorted_by_name, data)
  end
  table.sort(sorted_by_name, function(a, b)
    return a.path < b.path
  end)

  common.log("Starting Pass 2: Building Markdown table")
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. total_size_str .. " will be analyzed under project root " .. project_root .. ":\n")

  local header1 = "Sorted by Size (Desc)"
  local header2 = "Sorted by Name (Asc)"

  local col1_width = math.max(#header1, max_display_length_size)
  local col2_width = math.max(#header2, max_display_length_name)
  common.log("Calculated column widths: Col1=" .. col1_width .. ", Col2=" .. col2_width)

  local function pad_right(str, width)
    if #str >= width then
      return str
    end
    return str .. string.rep(" ", width - #str)
  end

  table.insert(result_lines, "| " .. pad_right(header1, col1_width) .. " | " .. pad_right(header2, col2_width) .. " |")
  table.insert(result_lines, "|-" .. string.rep("-", col1_width) .. "-|-" .. string.rep("-", col2_width) .. "-|")

  for i = 1, #sorted_by_size do
    local display_size = sorted_by_size[i].display_size
    local display_name = sorted_by_name[i].display_name
    local padded_display_size = pad_right(display_size, col1_width)
    local padded_display_name = pad_right(display_name, col2_width)
    table.insert(result_lines, "| " .. padded_display_size .. " | " .. padded_display_name .. " |")
  end
  common.log("Pass 2 Complete. Table built.")

  return table.concat(result_lines, "\n")
end

return aiconfig

