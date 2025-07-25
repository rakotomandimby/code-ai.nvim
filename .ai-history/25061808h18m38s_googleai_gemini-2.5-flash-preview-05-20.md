# Have a configuration option to control system instructions appending  

The normal way to run this plugin is to take the user provided system instructions and append the embeded system instructions to it then send it to the AI model.

I would like to introduce an exception to this rule: if the command used to run the plugin has a configuration option `append_embeded_system_instructions` set to false, then the plugin should not append the embedded system instructions to the user provided ones before sending them to the AI model.

The defult behavior should remain unchanged, meaning that if the configuration option is not set or set to true, the plugin should append the embedded system instructions as usual.

There should be a global configuration option that can be set to control this behavior, and it should be possible to override this option on a per-command basis.

Tell me the full new code of the files I need to change in order to implement this feature.


# GGL Implement a configuration option to control system instructions appending

We will implement a new configuration option `append_embedded_system_instructions` that allows users to control whether the plugin appends the embedded system instructions to the user-provided ones. This option will have a global default that can be overridden on a per-command basis.

To achieve this, we will modify two files:
1.  `lua/ai/init.lua`: We will add the new configuration option to `M.opts` and update the `M.handle` function to determine the effective value of this option (global or command-specific) and pass it to the `aiconfig.getSystemInstructions` function.
2.  `lua/ai/aiconfig.lua`: We will modify the `aiconfig.getSystemInstructions` function to accept a new parameter that dictates whether the embedded system instructions should be appended. The logic for reading and appending the `common-system-instructions.md` file will be conditional on this new parameter.

No other files need to be changed as they only consume the final system instruction string.

## File: lua/ai/init.lua

We will add `append_embedded_system_instructions = true` to the `M.opts` table to set its default value. Then, in the `M.handle` function, we will determine the value of `append_embedded_system_instructions` by checking the command's definition first, then falling back to the global option. This determined value will then be passed as an argument to `aiconfig.getSystemInstructions`.

```lua
local anthropic = require('ai.anthropic.query')
local googleai = require('ai.googleai.query')
local openai = require('ai.openai.query')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')

local default_prompts = {
  introduce = {
    command = 'AIIntroduceYourself',
    loading_tpl = 'Loading...',
    prompt_tpl = 'Say who you are, your version, and the currently used model',
    result_tpl = '${output}',
    require_input = false,
  }
}

local M = {}
M.opts = {
  anthropic_model = '',
  googleai_model = '',
  openai_model = '',

  anthropic_agent_host = '',
  googleai_agent_host = '',
  openai_agent_host = '',

  anthropic_api_key = '',
  googleai_api_key = '',
  openai_api_key = '',

  locale = 'en',
  alternate_locale = 'fr',
  result_popup_gets_focus = false,
  -- START: Added new configuration options for upload feature
  upload_url = '',
  upload_token = '',
  upload_as_public = false, -- New configuration option with default value false
  -- END: Added new configuration options for upload feature
  append_embedded_system_instructions = true, -- New configuration option with default value true
}
M.prompts = default_prompts
local win_id

local function splitLines(input)
  local lines = {}
  local offset = 1
  while offset > 0 do
    local i = string.find(input, '\n', offset)
    if i == nil then
      table.insert(lines, string.sub(input, offset, -1))
      offset = 0
    else
      table.insert(lines, string.sub(input, offset, i - 1))
      offset = i + 1
    end
  end
  return lines
end

local function joinLines(lines)
  local result = ""
  for _, line in ipairs(lines) do
    result = result .. line .. "\n"
  end
  return result
end

local function isEmpty(text)
  return text == nil or text == ''
end

function M.hasLetters(text)
  return type(text) == 'string' and text:match('[a-zA-Z]') ~= nil
}

function M.getSelectedText(esc)
  if esc then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<esc>', true, false, true), 'n', false)
  end
  local vstart = vim.fn.getpos("'<")
  local vend = vim.fn.getpos("'>")
  local ok, lines = pcall(vim.api.nvim_buf_get_text, 0, vstart[2] - 1, vstart[3] - 1, vend[2] - 1, vend[3], {})
  if ok then
    return joinLines(lines)
  else
    lines = vim.api.nvim_buf_get_lines(0, vstart[2] - 1, vend[2], false)
    return joinLines(lines)
  end
end

function M.close()
  if win_id == nil or win_id == vim.api.nvim_get_current_win() then
    return
  end
  pcall(vim.api.nvim_win_close, win_id, true)
  win_id = nil
}

function M.createPopup(initialContent, width, height)
  M.close()
  local bufnr = vim.api.nvim_create_buf(false, true)

  local update = function(content)
    if content == nil then
      content = ''
    end
    local lines = splitLines(content)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    vim.bo[bufnr].modifiable = false
  end

  win_id = vim.api.nvim_open_win(bufnr, false, {
    relative = 'cursor',
    border = 'single',
    title = 'code-ai.md',
    style = 'minimal',
    width = width,
    height = height,
    row = 1,
    col = 0,
  })
  vim.bo[bufnr].filetype = 'markdown'
  vim.api.nvim_win_set_option(win_id, 'wrap', true)


  update(initialContent)
  if M.opts.result_popup_gets_focus then
    vim.api.nvim_set_current_win(win_id)
  end
  return update
end

function M.fill(tpl, args)
  if tpl == nil then
    tpl = ''
  else
    for key, value in pairs(args) do
      tpl = string.gsub(tpl, '%${' .. key .. '}', value)
    end
  end
  return tpl
end


function M.handle(name, input)
  local def = M.prompts[name]
  local width = vim.fn.winwidth(0)
  local height = vim.fn.winheight(0)
  local args = {
    locale = M.opts.locale,
    alternate_locale = M.opts.alternate_locale,
    input = input,
    input_encoded = vim.fn.json_encode(input),
  }

  local number_of_files = #aiconfig.listScannedFilesFromConfig()
  local use_anthropic_agent = M.opts.anthropic_agent_host ~= ''
  local use_googleai_agent = M.opts.googleai_agent_host ~= ''
  local use_openai_agent = M.opts.openai_agent_host ~= ''

  local update = nil

  if (number_of_files == 0 or not use_anthropic_agent or not use_googleai_agent or not use_openai_agent ) then
    update = M.createPopup(M.fill(def.loading_tpl , args), width - 8, height - 4)
  else
    local scanned_files = aiconfig.listScannedFilesAsFormattedTable()
    update = M.createPopup(M.fill(def.loading_tpl .. scanned_files, args), width - 8, height - 4)
  end
  local prompt = M.fill(def.prompt_tpl, args)

  -- Determine whether to append embedded system instructions
  local append_embedded_system_instructions = true -- Default to true
  if def.append_embedded_system_instructions ~= nil then
    append_embedded_system_instructions = def.append_embedded_system_instructions
  elseif M.opts.append_embedded_system_instructions ~= nil then
    append_embedded_system_instructions = M.opts.append_embedded_system_instructions
  end

  -- Get system instructions from file or fall back to command definition
  -- Pass the new flag to aiconfig.getSystemInstructions
  local instruction = aiconfig.getSystemInstructions(append_embedded_system_instructions)

  -- Determine which models to use
  local anthropic_model = def.anthropic_model or M.opts.anthropic_model
  local googleai_model = def.googleai_model or M.opts.googleai_model
  local openai_model = def.openai_model or M.opts.openai_model

  -- If command-level models are set, use them
  if def.anthropic_model and def.anthropic_model ~= '' then
    anthropic_model = def.anthropic_model
  end
  if def.googleai_model and def.googleai_model ~= '' then
    googleai_model = def.googleai_model
  end
  if def.openai_model and def.openai_model ~= '' then
    openai_model = def.openai_model
  end

  -- START: Prepare common options for all LLM queries, including upload details
  local common_query_opts = {
    upload_url = M.opts.upload_url,
    upload_token = M.opts.upload_token,
    upload_as_public = M.opts.upload_as_public, -- Pass the new configuration option
  }
  -- END: Prepare common options for all LLM queries

  local function handleResult(output, output_key)
    args[output_key] = output
    args.output = (args.anthropic_output or '').. (args.googleai_output or '') .. (args.openai_output or '')
    update(M.fill(def.result_tpl or '${output}', args))
  end

  local askHandleResultAndCallbackAnthropic = {
    handleResult = function(output) return handleResult(output, 'anthropic_output') end,
    callback = function() end,
    upload_url = common_query_opts.upload_url,
    upload_token = common_query_opts.upload_token,
    upload_as_public = common_query_opts.upload_as_public, -- Pass the new configuration option
  }

  local askHandleResultAndCallbackGoogleAI = {
    handleResult = function(output) return handleResult(output, 'googleai_output') end,
    callback = function() end,
    upload_url = common_query_opts.upload_url,
    upload_token = common_query_opts.upload_token,
    upload_as_public = common_query_opts.upload_as_public, -- Pass the new configuration option
  }

  local askHandleResultAndCallbackOpenAI = {
    handleResult = function(output) return handleResult(output, 'openai_output') end,
    callback = function() end,
    upload_url = common_query_opts.upload_url,
    upload_token = common_query_opts.upload_token,
    upload_as_public = common_query_opts.upload_as_public, -- Pass the new configuration option
  }

  if (number_of_files == 0
        or not use_anthropic_agent
        or not use_googleai_agent
        or not use_openai_agent) then
    common.log("Not using agents")
    anthropic.askLight(
      anthropic_model,
      instruction,
      prompt,
      askHandleResultAndCallbackAnthropic,
      M.opts.anthropic_api_key,
      common_query_opts.upload_url,
      common_query_opts.upload_token,
      common_query_opts.upload_as_public -- Pass the new configuration option
    )
    googleai.askLight(
      googleai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackGoogleAI,
      M.opts.googleai_api_key,
      common_query_opts.upload_url,
      common_query_opts.upload_token,
      common_query_opts.upload_as_public -- Pass the new configuration option
    )
    openai.askLight(
      openai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackOpenAI,
      M.opts.openai_api_key,
      common_query_opts.upload_url,
      common_query_opts.upload_token,
      common_query_opts.upload_as_public -- Pass the new configuration option
    )
  else
    common.log("Using agents")
    anthropic.askHeavy(
      anthropic_model,
      instruction,
      prompt,
      askHandleResultAndCallbackAnthropic,
      M.opts.anthropic_agent_host,
      common_query_opts.upload_url,
      common_query_opts.upload_token,
      common_query_opts.upload_as_public -- Pass the new configuration option
    )
    googleai.askHeavy(
      googleai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackGoogleAI,
      M.opts.googleai_agent_host,
      common_query_opts.upload_url,
      common_query_opts.upload_token,
      common_query_opts.upload_as_public -- Pass the new configuration option
    )
    openai.askHeavy(
      openai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackOpenAI,
      M.opts.openai_agent_host,
      common_query_opts.upload_url,
      common_query_opts.upload_token,
      common_query_opts.upload_as_public -- Pass the new configuration option
    )
  end
end

function M.assign(table, other)
  for k, v in pairs(other) do
    table[k] = v
  end
  return table
end

function M.setup(opts)
  for k, v in pairs(opts) do
    if k == 'prompts' then
      M.prompts = {}
      M.assign(M.prompts, default_prompts)
      M.assign(M.prompts, v)
    elseif M.opts[k] ~= nil then
      M.opts[k] = v
    end
  end
  for k, v in pairs(M.prompts) do
    if v.command then
      vim.api.nvim_create_user_command(v.command, function(args)
        local text = args['args']
        if isEmpty(text) then
          text = M.getSelectedText(true)
        end
        if not v.require_input or M.hasLetters(text) then
          M.handle(k, text)
        end
      end, { range = true, nargs = '?' })
    end
  end

  if M.opts.anthropic_model == '' or  M.opts.googleai_model == '' or M.opts.openai_model == '' then
    error('You need to set both anthropic_model and googleai_model and openai_model')
  end
  if M.opts.anthropic_api_key ==''or M.opts.googleai_api_key == '' or M.opts.openai_api_key == '' then
    error('You need to set both anthropic_api_key and googleai_api_key and openai_api_key')
  end

  vim.api.nvim_create_user_command('AIListScannedFiles', function()
    local width = vim.fn.winwidth(0)
    local height = vim.fn.winheight(0)
    local scanned_files = aiconfig.listScannedFilesAsFormattedTable()
    local update = M.createPopup(scanned_files, width - 12, height - 8)
    update(scanned_files)
  end, {})

  vim.api.nvim_create_user_command('AIShowSystemInstructions', function()
    local width = vim.fn.winwidth(0)
    local height = vim.fn.winheight(0)
    local instructions = aiconfig.getSystemInstructions()
    local update = M.createPopup(instructions, width - 12, height - 8)
    update(instructions)
  end, {})
end

vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  callback = M.close,
})

return M

```

## File: lua/ai/aiconfig.lua

We will modify the `aiconfig.getSystemInstructions` function to accept an optional boolean parameter `append_common_instructions`. The existing logic for finding and appending `common-system-instructions.md` will be wrapped in an `if` condition that checks this parameter. If the parameter is not provided, it will default to `true` to maintain the current behavior.

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

function aiconfig.getSystemInstructions(append_common_instructions)
  -- Default to true if not provided, maintaining current behavior
  append_common_instructions = append_common_instructions == nil or append_common_instructions

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

  if append_common_instructions then
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
  end -- End of if append_common_instructions
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

GoogleAI gemini-2.5-flash-preview-05-20 (18k in, 8k out)


