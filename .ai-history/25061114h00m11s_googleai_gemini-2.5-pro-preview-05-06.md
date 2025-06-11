# Replace built-in Lua file access with vim's built-in functions

I think I access filesystem with built-in Lua functions like `io.open`, `io.read`, etc.
I should use vim's built-in functions like `vim.fn.readfile`, `vim.fn.writefile`, etc. instead.

Tell the relevant code to replace and give me the full fixed file contents.


# GGL Replace built-in Lua file access with vim's built-in functions

We will refactor the codebase to replace standard Lua `io` library calls for file system operations with Neovim's built-in `vim.fn` functions. This change enhances integration with Neovim's environment, potentially improving performance, error handling, and consistency with Vimscript practices. Specifically, `io.open`, `file:read()`, `file:write()`, `file:close()`, and `io.lines()` will be replaced by functions like `vim.fn.filereadable()`, `vim.fn.readfile()`, and `vim.fn.writefile()`.

The following files will be modified:
- `lua/ai/aiconfig.lua`
- `lua/ai/common.lua`
- `lua/ai/history.lua`

## `lua/ai/aiconfig.lua`

We will update this file to use `vim.fn.filereadable()` for checking file existence, `vim.fn.readfile()` for reading file content, and iterate over lines read by `vim.fn.readfile()` instead of using `io.lines()`.

```lua
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

function aiconfig.getSystemInstructions()
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

function aiconfig.listScannedFilesAsFormattedTable()
  local analyzed_files_paths = aiconfig.listScannedFilesFromConfig()
  local project_root = aiconfig.getProjectRoot()

  if #analyzed_files_paths == 0 then
    return "# No files to analyze under project root " .. project_root
  end

  local files_data = {}
  local total_size = 0
  local max_display_length = 0

  common.log("Starting Pass 1: Gathering file data and calculating max display length")
  for _, relative_path in ipairs(analyzed_files_paths) do
    local full_path = project_root .. '/' .. relative_path
    local stat = vim.loop.fs_stat(full_path)
    local size = stat and stat.size or 0
    total_size = total_size + size
    local size_str = format_size(size)
    local display_str = relative_path .. " (" .. size_str .. ")"
    max_display_length = math.max(max_display_length, #display_str)
    table.insert(files_data, {
      path = relative_path,
      size = size,
      size_str = size_str,
      display_str = display_str
    })
    common.log("Processed: " .. display_str .. " (Length: " .. #display_str .. ")")
  end
  common.log("Pass 1 Complete. Max display length: " .. max_display_length)

  local sorted_by_size = files_data

  local sorted_by_name = {}
  for _, data in ipairs(files_data) do
    table.insert(sorted_by_name, data)
  end
  table.sort(sorted_by_name, function(a, b)
    return a.path < b.path
  end)

  local total_size_str = format_size(total_size)

  common.log("Starting Pass 2: Building Markdown table")
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. total_size_str .. " will be analyzed under project root " .. project_root .. ":\n")

  local header1 = "Sorted by Size (Desc)"
  local header2 = "Sorted by Name (Asc)"

  local col1_width = math.max(#header1, max_display_length)
  local col2_width = math.max(#header2, max_display_length)
  common.log("Calculated column widths: Col1=" .. col1_width .. ", Col2=" .. col2_width)

  local function pad_right(str, width)
    return str .. string.rep(" ", width - #str)
  end

  table.insert(result_lines, "| " .. pad_right(header1, col1_width) .. " | " .. pad_right(header2, col2_width) .. " |")
  table.insert(result_lines, "|-" .. string.rep("-", col1_width) .. "-|-" .. string.rep("-", col2_width) .. "-|")

  for i = 1, #sorted_by_size do
    local display_size = sorted_by_size[i].display_str
    local display_name = sorted_by_name[i].display_str
    local padded_display_size = pad_right(display_size, col1_width)
    local padded_display_name = pad_right(display_name, col2_width)
    table.insert(result_lines, "| " .. padded_display_size .. " | " .. padded_display_name .. " |")
  end
  common.log("Pass 2 Complete. Table built.")

  return table.concat(result_lines, "\n")
end

return aiconfig
```

## `lua/ai/common.lua`

We will modify the `common.log` function to use `vim.fn.writefile()` with the append flag (`"a"`) for writing log messages.

```lua
local common = {}
local curl = require('plenary.curl') -- Added curl dependency for upload

function common.log(message)
  local log_path = "/tmp/aiconfig.log"
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local full_log_message = "[ " .. timestamp .. " ] -- " .. message

  -- writefile expects a list of strings. Each string is a line.
  -- It adds newlines between elements, not after the last one if it's a single line.
  -- So, we pass a list containing one string.
  -- The "a" flag appends to the file.
  if vim.fn.writefile({full_log_message}, log_path, "a") == -1 then
    -- If logging itself fails, print an error to Neovim's message area.
    -- Avoid using common.log here to prevent potential recursion if the error is persistent.
    vim.api.nvim_err_writeln("Error: Could not write to log file: " .. log_path)
  end
end

function common.uploadContent(url, token, content, model_name, is_public)
  if url == '' or token == '' then
    common.log("Upload URL or Token not configured. Skipping upload for " .. model_name .. " response.")
    return -- Early return if not configured
  end

  if model_name ~= 'disabled' then
    common.log("Attempting to upload " .. model_name .. " response to: " .. url)

    local headers = {
      ['Content-Type'] = 'text/markdown',
      ['X-MarkdownBlog-Token'] = token
    }
    -- Add public header if upload_as_public is true
    if is_public == true then
      headers['X-MarkdownBlog-Public'] = 'true'
      common.log("Setting upload as public for " .. model_name)
    end

    common.log("Uploading content for model: " .. model_name)
    curl.put(url,
      {
        headers = headers,
        body = content,
        callback = function(res)
          if res.status >= 200 and res.status < 300 then
            common.log("Successfully uploaded " .. model_name .. " response. Status: " .. res.status)
          else
            common.log("Failed to upload " .. model_name .. " response. Status: " .. res.status .. ", Body: " .. res.body)
          end
        end
      })
  else
    common.log("Model is disabled. Skipping upload.")
  end
end

function common.askCallback(res, opts, formatResult)
  local result
  if res.status ~= 200 then
    if opts.handleError ~= nil then
      result = opts.handleError(res.status, res.body)
    else
      common.log("Error: API responded with the status " .. tostring(res.status) .. '\n\n' .. res.body)
      result = 'Error: API responded with the status ' .. tostring(res.status) .. '\n\n' .. res.body
    end
  else
    local data = vim.fn.json_decode(res.body)
    -- Pass upload_url, upload_token, and upload_as_public to formatResult
    result = formatResult(data, opts.upload_url, opts.upload_token, opts.upload_as_public) -- Modified: Pass upload_as_public option
    if opts.handleResult ~= nil then
      result = opts.handleResult(result)
    end
  end
  opts.callback(result)
end

function common.insertWordToTitle(word_to_insert, text)
  local lines = vim.split(text, '\n', { plain = true })
  if #lines == 0 then
    return text
  end

  -- Check if the first line starts with a title
  if lines[1]:sub(1, 1) == '#' then
    -- Insert the word at the beginning of the first line
    lines[1] = lines[1]:gsub('^# ', '# ' .. word_to_insert .. ' ')
  else
    -- Prepend a new title with the word
    lines[1] = '# ' .. word_to_insert .. ' ' .. lines[1]
  end

  return table.concat(lines, '\n')
end

return common
```

## `lua/ai/history.lua`

We will update `history.saveToHistory` to use `vim.fn.writefile()` for saving content to history files. `vim.split()` will be used to convert the content string into a list of lines as expected by `vim.fn.writefile()`.

```lua
local history = {}
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')

-- Create the '.ai-history' directory under the project root if it doesn't exist
function history.createHistoryDir()
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  common.log("Checking if history directory exists: " .. historyDir)
  local historyDirExists = vim.fn.isdirectory(historyDir) == 1
  if not historyDirExists then
    vim.fn.mkdir(historyDir, 'p')
    common.log("Created history directory: " .. historyDir)
  end
end

function history.saveToHistory(model, content)
  common.log("Saving history to " .. model .. " history file")
  history.createHistoryDir()
  common.log("Creating history file for " .. model)
  local fileName = os.date("%Y%m%d%Hh%Mm%Ss") .. "_" .. model .. ".md"
  -- remove the 2 first characters of the filename, because it is century and we dont need it
  fileName = string.sub(fileName, 3)
  local filePath = aiconfig.getProjectRoot() .. '/.ai-history/' .. fileName
  
  common.log("Writing to history file: " .. filePath)
  -- vim.fn.writefile expects a list of strings (lines).
  -- The `true` in vim.split keeps trailing empty lines, which might be important for Markdown.
  local lines_to_write = vim.split(content, '\n', true)
  
  if vim.fn.writefile(lines_to_write, filePath) == 0 then
    common.log("Successfully wrote history file: " .. filePath)
    history.removeOldestHistoryFiles(15)
    return filePath
  else
    common.log("Failed to write history file: " .. filePath)
    return nil
  end
end

-- list files in the '.ai-history' directory, ordered by filename
function history.listHistoryFiles()
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  if vim.fn.isdirectory(historyDir) ~= 1 then
    common.log("History directory does not exist: " .. historyDir)
    return {}
  end
  local files = vim.fn.readdir(historyDir)
  table.sort(files)
  -- common.log("Files in history folder (sorted):") -- Log moved to removeOldestHistoryFiles for clarity
  -- for i, file in ipairs(files) do
  --   common.log("File " .. i .. ": " .. file)
  -- end
  return files
end

-- Remove the oldest history files to keep only the specified number of most recent files
function history.removeOldestHistoryFiles(numberOfFilesToKeep)
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  local files = history.listHistoryFiles()

  if #files == 0 and vim.fn.isdirectory(historyDir) ~= 1 then
    -- listHistoryFiles already logged this, or directory doesn't exist.
    return
  end

  common.log("Files in history folder (" .. #files .. " total):")
  for i, file in ipairs(files) do
    common.log("File " .. i .. ": " .. file)
  end

  local files_to_remove_count = #files - numberOfFilesToKeep
  if files_to_remove_count > 0 then
    common.log(string.format("Need to remove %d oldest files to keep %d.", files_to_remove_count, numberOfFilesToKeep))
    -- Delete the oldest files (which are at the beginning of the sorted array)
    for i = 1, files_to_remove_count do
      local file_to_delete = files[i]
      local filePath_to_delete = historyDir .. '/' .. file_to_delete
      if vim.fn.delete(filePath_to_delete) == 0 then
        common.log("Deleted oldest history file: " .. filePath_to_delete)
      else
        common.log("Failed to delete history file: " .. filePath_to_delete)
      end
    end
  else
    common.log("No old history files to remove (found " .. #files .. ", keeping " .. numberOfFilesToKeep .. ").")
  end
end

return history
```

GoogleAI (18k in, 6k out)

