# In `common.lua`, `vim.api.nvim_err_writeln()` is reported to be deprecated.

There are some deprecated functions use in the whole codebase, like `vim.api.nvim_err_writeln()`.
Analyze the codebase, find deprecated functions calls and tell me the whole new content of any file I have to modify in order not to use deprecated functions anymore.



# GGL Summary of Changes to Address Deprecated Functions

We will update the codebase to replace deprecated Neovim API function calls with their modern equivalents. This primarily involves replacing `vim.api.nvim_err_writeln()` with `vim.notify()`, several `vim.fn.*` functions with their `vim.json.*`, `vim.uv.*`, or `vim.fs.*` counterparts (e.g., `vim.fn.getcwd()` with `vim.uv.cwd()`, `vim.fn.isdirectory()` with checks on `vim.uv.fs_stat().type`, `vim.fn.mkdir()` with `vim.fs.mkdir()`, `vim.fn.readdir()` with `vim.fs.dir()`, `vim.fn.delete()` with `os.remove()`, and `vim.fn.json_decode()` with `vim.json.decode()`). We will also update direct property access like `vim.bo` to use `vim.api.nvim_buf_set_option()`.

The following files will be modified:
- `lua/ai/common.lua`
- `lua/ai/init.lua`
- `lua/ai/aiconfig.lua`
- `lua/ai/history.lua`
- `lua/ai/googleai/query.lua`
- `lua/ai/openai/query.lua`
- `lua/ai/anthropic/query.lua`

We will keep `vim.fn.readfile()` and `vim.fn.glob()` for now, as they are not strictly deprecated and their replacements can be more verbose without significant functional improvement for their current usage patterns.

---

## `lua/ai/common.lua`

We replaced `vim.api.nvim_err_writeln()` with `vim.notify()` for error reporting and `vim.fn.json_decode()` with `vim.json.decode()`.

```lua
local common = {}
local curl = require('plenary.curl') -- Added curl dependency for upload

function common.log(message)
  local log_path = "/tmp/aiconfig.log"
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local full_log_message = "[ " .. timestamp .. " ] -- " .. message .. "\n"

  -- Use native Lua file I/O instead of vim.fn.writefile
  local file, err = io.open(log_path, "a")
  if not file then
    -- If logging itself fails, print an error to Neovim's message area.
    -- Using pcall to safely attempt the error write in case we're still in a fast context
    pcall(function()
      vim.notify("Error: Could not open log file: " .. log_path .. " - " .. (err or "unknown error"), vim.log.levels.ERROR)
    end)
    return
  end
  
  file:write(full_log_message)
  file:close()
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
    local success, data = pcall(vim.json.decode, res.body)
    if not success then
      common.log("Error: Failed to decode JSON response: " .. tostring(data)) -- data is error message here
      result = "Error: Failed to decode JSON response from API."
      if opts.handleError then
        result = opts.handleError(0, "Failed to decode JSON: " .. tostring(data)) -- status 0 or similar to indicate client-side error
      end
    else
      -- Pass upload_url, upload_token, and upload_as_public to formatResult
      result = formatResult(data, opts.upload_url, opts.upload_token, opts.upload_as_public) -- Modified: Pass upload_as_public option
      if opts.handleResult ~= nil then
        result = opts.handleResult(result)
      end
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

---

## `lua/ai/init.lua`

We updated `vim.bo[bufnr].modifiable` to use `vim.api.nvim_buf_set_option()`, `vim.fn.json_encode()` to `vim.json.encode()`, and `vim.fn.winwidth()`/`vim.fn.winheight()` to their `vim.api.nvim_win_get_width()`/`vim.api.nvim_win_get_height()` equivalents.

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
end

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
end

function M.createPopup(initialContent, width, height)
  M.close()
  local bufnr = vim.api.nvim_create_buf(false, true)

  local update = function(content)
    if content == nil then
      content = ''
    end
    local lines = splitLines(content)
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
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
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(bufnr, 'wrap', true)
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
  local width = vim.api.nvim_win_get_width(0)
  local height = vim.api.nvim_win_get_height(0)
  local args = {
    locale = M.opts.locale,
    alternate_locale = M.opts.alternate_locale,
    input = input,
    input_encoded = vim.json.encode(input),
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
  -- Get system instructions from file or fall back to command definition
  local instruction = aiconfig.getSystemInstructions()

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
    local width = vim.api.nvim_win_get_width(0)
    local height = vim.api.nvim_win_get_height(0)
    local scanned_files = aiconfig.listScannedFilesAsFormattedTable()
    local update = M.createPopup(scanned_files, width - 12, height - 8)
    update(scanned_files)
  end, {})

  vim.api.nvim_create_user_command('AIShowSystemInstructions', function()
    local width = vim.api.nvim_win_get_width(0)
    local height = vim.api.nvim_win_get_height(0)
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

---

## `lua/ai/aiconfig.lua`

We replaced `vim.fn.getcwd()` with `vim.uv.cwd()`, `vim.fn.filereadable()` with a check on `vim.uv.fs_stat().type`, `vim.fn.fnamemodify(path, ":h")` with `vim.fs.dirname()`, `vim.fn.finddir()`/`vim.fn.findfile()` with `vim.fs.find()`, and `vim.loop.fs_stat()` with `vim.uv.fs_stat()`. Error handling for `vim.uv.cwd()` returning `nil` has been added.

```lua
local aiconfig = {}
local common = require("ai.common")
local globpattern = require("ai.globpattern")

function aiconfig.findSystemInstructionsFile()
  local current_dir = vim.uv.cwd()
  if not current_dir then
    common.log("findSystemInstructionsFile: Failed to get current working directory.")
    return ""
  end
  local path = current_dir .. '/.ai-system-instructions.md'
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == 'file' then
    return path
  else
    return ""
  end
end

function aiconfig.getSystemInstructions()
  local user_instructions_path = aiconfig.findSystemInstructionsFile()
  local content = ""
  if user_instructions_path ~= "" then
    local lines = vim.fn.readfile(user_instructions_path) -- Kept for simplicity
    if lines and #lines > 0 then
      content = table.concat(lines, "\n")
    else
      common.log("Could not read user system instructions or file is empty: " .. user_instructions_path)
    end
  end

  local common_instructions_paths = vim.api.nvim_get_runtime_file("lua/ai/common-system-instructions.md", false)
  local common_content_found = false

  if #common_instructions_paths > 0 then
    local common_instructions_path = common_instructions_paths[1]
    common.log("Found common system instructions at: " .. common_instructions_path)
    local stat = vim.uv.fs_stat(common_instructions_path)
    if stat and stat.type == 'file' then
      local common_lines = vim.fn.readfile(common_instructions_path) -- Kept for simplicity
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
      common.log("Common system instructions file not readable or not a file: " .. common_instructions_path)
    end
  else
    common.log("Common system instructions file not found in runtime paths via nvim_get_runtime_file.")
  end

  if not common_content_found then
    common.log("Common system instructions not found via runtime path, trying fallback.")
    local current_file_info = debug.getinfo(1, "S")
    if current_file_info and current_file_info.source and current_file_info.source:sub(1,1) == "@" then
        local current_file_path = current_file_info.source:sub(2)
        local plugin_lua_ai_dir = vim.fs.dirname(current_file_path)
        if plugin_lua_ai_dir then
            local fallback_path = plugin_lua_ai_dir .. "/common-system-instructions.md"
            common.log("Trying fallback path: " .. fallback_path)
            local stat_fallback = vim.uv.fs_stat(fallback_path)
            if stat_fallback and stat_fallback.type == 'file' then
              local fallback_lines = vim.fn.readfile(fallback_path) -- Kept for simplicity
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
              common.log("Could not find common system instructions at fallback path (not readable or not a file): " .. fallback_path)
            end
        else
            common.log("Could not determine plugin directory for fallback common system instructions.")
        end
    else
        common.log("Could not determine current file path for fallback common system instructions.")
    end
  end
  return content
end

function aiconfig.findScannedFilesConfig()
  local current_dir = vim.uv.cwd()
  if not current_dir then
    common.log("findScannedFilesConfig: Failed to get current working directory.")
    return ""
  end
  local path = current_dir .. '/.ai-scanned-files'
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == 'file' then
    return path
  else
    return ""
  end
end

function aiconfig.getProjectRoot()
  local current_dir = vim.uv.cwd()
  if not current_dir then
    common.log("getProjectRoot: Critical error - Failed to get current working directory.")
    return "" -- Return empty string to indicate failure
  end

  local configFile = aiconfig.findScannedFilesConfig() -- This function uses vim.uv.cwd()
  if configFile ~= "" then
    local dir = vim.fs.dirname(configFile)
    return dir or current_dir -- Fallback if dirname fails (should not for valid path)
  end

  local search_opts_base = { path = current_dir, upward = true, limit = 1 }

  local search_opts_dir = vim.deepcopy(search_opts_base)
  search_opts_dir.type = "directory"
  local git_dirs = vim.fs.find({".git"}, search_opts_dir)
  if git_dirs and #git_dirs > 0 and git_dirs[1] then
    local dir = vim.fs.dirname(git_dirs[1])
    return dir or current_dir
  end

  local search_opts_file = vim.deepcopy(search_opts_base)
  search_opts_file.type = "file"
  local gitignore_files = vim.fs.find({".gitignore"}, search_opts_file)
  if gitignore_files and #gitignore_files > 0 and gitignore_files[1] then
    local dir = vim.fs.dirname(gitignore_files[1])
    return dir or current_dir
  end

  local readme_files = vim.fs.find({"README.md", "readme.md"}, search_opts_file)
  if readme_files and #readme_files > 0 and readme_files[1] then
    local dir = vim.fs.dirname(readme_files[1])
    return dir or current_dir
  end

  return current_dir -- Fallback to the current working directory
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
  local lines = vim.fn.readfile(config_path) -- Kept for simplicity
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
  if project_root == "" then
    common.log("listScannedFilesFromConfig: Could not determine project root. Aborting scan.")
    return {}
  end

  for _, include_pattern in ipairs(include_glob_patterns) do
    common.log("Processing include glob pattern: " .. include_pattern)
    local potential_files = vim.fn.glob(project_root .. '/' .. include_pattern, false, true) -- Kept for simplicity

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
          local file_info = vim.uv.fs_stat(full_path)
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
  local project_root = aiconfig.getProjectRoot()
  if project_root == "" then
    common.log("contentOf: Could not determine project root. Cannot read file: " .. file_relative_path)
    return ""
  end
  local full_path = project_root .. '/' .. file_relative_path
  local stat = vim.uv.fs_stat(full_path)
  if stat and stat.type == 'file' then
    local lines = vim.fn.readfile(full_path) -- Kept for simplicity
    if lines then
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
  if project_root == "" then
    common.log("listScannedFilesAsFormattedTable: Could not determine project root.")
    return "# No files to analyze (could not determine project root)"
  end

  if #analyzed_files_paths == 0 then
    return "# No files to analyze under project root " .. project_root
  end

  local files_data = {}
  local total_size = 0
  local max_display_length = 0

  common.log("Starting Pass 1: Gathering file data and calculating max display length")
  for _, relative_path in ipairs(analyzed_files_paths) do
    local full_path = project_root .. '/' .. relative_path
    local stat = vim.uv.fs_stat(full_path)
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

---

## `lua/ai/history.lua`

We replaced `vim.fn.isdirectory()` with a check on `vim.uv.fs_stat().type`, `vim.fn.mkdir(path, 'p')` with `vim.fs.mkdir(path, { parents = true })`, `vim.fn.readdir()` with `vim.fs.dir()`, and `vim.fn.delete()` with `os.remove()`.

```lua
local history = {}
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')

-- Create the '.ai-history' directory under the project root if it doesn't exist
function history.createHistoryDir()
  local project_root = aiconfig.getProjectRoot()
  if project_root == "" then
    common.log("createHistoryDir: Could not determine project root. Cannot create history directory.")
    return
  end
  local historyDir = project_root .. '/.ai-history'
  common.log("Checking if history directory exists: " .. historyDir)
  
  local stat = vim.uv.fs_stat(historyDir)
  local historyDirExists = stat and stat.type == "directory"

  if not historyDirExists then
    local project_root_stat = vim.uv.fs_stat(project_root)
    if not (project_root_stat and project_root_stat.type == "directory") then
        common.log("Project root directory does not exist, cannot create history directory: " .. project_root)
        return
    end
    -- mode 0755 is 493 in decimal
    local success, err = pcall(vim.fs.mkdir, historyDir, { parents = true, mode = 493 })
    if success then
      common.log("Created history directory: " .. historyDir)
    else
      common.log("Failed to create history directory: " .. historyDir .. " Error: " .. tostring(err))
    end
  end
end

function history.saveToHistory(model, content)
  common.log("Saving history to " .. model .. " history file")
  history.createHistoryDir() -- Ensures directory exists

  local project_root = aiconfig.getProjectRoot()
  if project_root == "" then
    common.log("saveToHistory: Could not determine project root. Cannot save history.")
    return nil
  end

  common.log("Creating history file for " .. model)
  local fileName = os.date("%Y%m%d%Hh%Mm%Ss") .. "_" .. model .. ".md"
  fileName = string.sub(fileName, 3)
  local filePath = project_root .. '/.ai-history/' .. fileName

  common.log("Writing to history file: " .. filePath)
  local lines_to_write = vim.split(content, '\n')

  -- Using io.open for writing
  local file, err = io.open(filePath, "w")
  if not file then
    common.log("Failed to open history file for writing: " .. filePath .. " Error: " .. tostring(err))
    return nil
  end

  local write_success, write_err = file:write(content)
  file:close() -- Close file regardless of write success

  if write_success then
    common.log("Successfully wrote history file: " .. filePath)
    history.removeOldestHistoryFiles(15)
    return filePath
  else
    common.log("Failed to write to history file: " .. filePath .. " Error: " .. tostring(write_err))
    -- Attempt to remove partially written or empty file on failure
    os.remove(filePath)
    return nil
  end
end

-- list files in the '.ai-history' directory, ordered by filename
function history.listHistoryFiles()
  local project_root = aiconfig.getProjectRoot()
  if project_root == "" then
    common.log("listHistoryFiles: Could not determine project root.")
    return {}
  end
  local historyDir = project_root .. '/.ai-history'
  
  local stat = vim.uv.fs_stat(historyDir)
  if not (stat and stat.type == "directory") then
    common.log("History directory does not exist or is not a directory: " .. historyDir)
    return {}
  end

  local files_list = {}
  local dir_iter, err = vim.fs.dir(historyDir)
  if not dir_iter then
    common.log("Could not iterate over history directory: " .. historyDir .. " Error: " .. tostring(err))
    return {}
  end
  
  for name, type in dir_iter do
    if type == 'file' then -- Only add files
        table.insert(files_list, name)
    end
  end
  table.sort(files_list)
  return files_list
end

-- Remove the oldest history files to keep only the specified number of most recent files
function history.removeOldestHistoryFiles(numberOfFilesToKeep)
  local project_root = aiconfig.getProjectRoot()
  if project_root == "" then
    common.log("removeOldestHistoryFiles: Could not determine project root.")
    return
  end
  local historyDir = project_root .. '/.ai-history'
  local files = history.listHistoryFiles() -- This already checks for historyDir existence

  if #files == 0 then
    -- listHistoryFiles would have logged if dir doesn't exist or is empty.
    return
  end

  common.log("Files in history folder (" .. #files .. " total):")
  for i, file_name in ipairs(files) do -- Renamed 'file' to 'file_name' to avoid conflict
    common.log("File " .. i .. ": " .. file_name)
  end

  local files_to_remove_count = #files - numberOfFilesToKeep
  if files_to_remove_count > 0 then
    common.log(string.format("Need to remove %d oldest files to keep %d.", files_to_remove_count, numberOfFilesToKeep))
    for i = 1, files_to_remove_count do
      local file_to_delete_name = files[i]
      local filePath_to_delete = historyDir .. '/' .. file_to_delete_name
      local success, remove_err = os.remove(filePath_to_delete)
      if success then
        common.log("Deleted oldest history file: " .. filePath_to_delete)
      else
        common.log("Failed to delete history file: " .. filePath_to_delete .. " Error: " .. tostring(remove_err))
      end
    end
  else
    common.log("No old history files to remove (found " .. #files .. ", keeping " .. numberOfFilesToKeep .. ").")
  end
end

return history

```

---

## `lua/ai/googleai/query.lua`

We replaced `vim.fn.json_decode()` with `vim.json.decode()`.

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.formatResult(data, upload_url, upload_token, upload_as_public)
  common.log("Inside GoogleAI formatResult")
  local result = ''
  local candidates_number = #data['candidates']
  if candidates_number == 1 then
    if data['candidates'][1]['content'] == nil then
      result = '\n#GoogleAI error\n\nGoogleAI stopped with the reason: ' .. data['candidates'][1]['finishReason'] .. '\n'
      -- No upload for error
      return result
    else
      -- Extract token counts from the response
      local prompt_tokens = data['usageMetadata']['promptTokenCount'] or 0  -- Default to 0
      local answer_tokens = data['usageMetadata']['candidatesTokenCount'] or 0 -- Default to 0

      -- Format token counts (e.g., "30k", "2k")
      local formatted_prompt_tokens = string.format("%gk", math.floor(prompt_tokens / 1000))
      local formatted_answer_tokens = string.format("%gk", math.floor(answer_tokens / 1000))

      result = result .. data['candidates'][1]['content']['parts'][1]['text'] .. '\n\n' .. 'GoogleAI ' .. modelUsed .. ' (' .. formatted_prompt_tokens .. ' in, ' .. formatted_answer_tokens .. ' out)\n\n'
    end
  else
    result = '# There are ' .. candidates_number .. ' GoogleAI candidates\n'
    for i = 1, candidates_number do
      result = result .. '## GoogleAI Candidate number ' .. i .. '\n'
      result = result .. data['candidates'][i]['content']['parts'][1]['text'] .. '\n'
    end
  end
  result = common.insertWordToTitle('GGL', result)
  history.saveToHistory('googleai_' .. modelUsed  , promptToSave .. '\n\n' .. result)

  -- START: Upload the formatted result with public option
  common.uploadContent(upload_url, upload_token, result, 'GoogleAI (' .. modelUsed .. ')', upload_as_public)
  -- END: Upload the formatted result with public option

  return result
end

-- Added a new function to handle and format GoogleAI API errors
function query.formatError(status, body)
  common.log("Formatting GoogleAI API error: " .. body)
  local error_result
  -- Try to parse the error JSON
  local success, error_data = pcall(vim.json.decode, body)
  if success and error_data and error_data.error then
    -- Extract specific error information
    local error_code = error_data.error.code or status
    local error_message = error_data.error.message or "Unknown error occurred"
    local error_status = error_data.error.status or "ERROR"
    error_result = string.format(
      "# GoogleAI API Error (%s)\n\n**Error Code**: %s\n**Status**: %s\n**Message**: %s\n",
      status,
      error_code,
      error_status,
      error_message
    )
  else
    -- Fallback for unexpected error format
    error_result = string.format("# GoogleAI API Error (%s)\n\n```\n%s\n```", status, body)
  end
  return error_result
end

query.askCallback = function(res, opts)
    local handleError = query.formatError  -- Set our custom error handler
    -- Modified: Pass upload_url, upload_token, and upload_as_public from opts to common.askCallback
    common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token, upload_as_public = opts.upload_as_public}, query.formatResult)
end

local disabled_response = {
  candidates = { { content = { parts = { { text = "GoogleAI models are disabled" } } }, finishReason = "STOP" } },
  usageMetadata = { promptTokenCount = 0, candidatesTokenCount = 0 }
}

-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.askHeavy(model, instruction, prompt, opts, agent_host, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  -- Check if model is disabled
  if model == "disabled" then
    -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
    return
  end

  local url = agent_host .. '/googleai'
  local project_context = aiconfig.listScannedFilesFromConfig()
  local body_chunks = {}
  table.insert(body_chunks, {system_instruction = instruction})
  table.insert(body_chunks, {role = 'user', content = "I need your help on this project. "})
  for _, context in pairs(project_context) do
    if aiconfig.contentOf(context) ~= nil then
      table.insert(body_chunks, {role = 'model', content = "What is the content of `" .. context .. "` ?"})
      table.insert(body_chunks, {role = 'user',  content = "The content of `" .. context .. "` is :\n```\n" .. aiconfig.contentOf(context) .. "\n```"})
    end
  end
  table.insert(body_chunks, {role = 'model', content = "Then what do you want me to do with all that information?"})
  table.insert(body_chunks, {role = 'user', content = prompt})
  table.insert(body_chunks, {model_to_use = model})
  table.insert(body_chunks, {temperature = 0.2})
  table.insert(body_chunks, {top_p = 0.5})
  table.insert(body_chunks, {})

  local function sendNextRequest(i)
    if i > #body_chunks then
      return
    end

    local message = body_chunks[i]
    local body = vim.json.encode(message)

    curl.post(url,
      {
        headers = {['Content-type'] = 'application/json'},
        body = body,
        callback = function(res)
          if i == #body_chunks then
            -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
            vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
          else
            sendNextRequest(i + 1)
          end
        end
      })
  end
  sendNextRequest(1)
end

-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
    return
  end

  local api_host = 'https://generativelanguage.googleapis.com'
  -- local api_host = 'https://eowloffrpvxwtqp.m.pipedream.net'
  local path = '/v1beta/models/' .. model .. ':generateContent'
  curl.post(api_host .. path,
    {
      headers = {
        ['Content-type'] = 'application/json',
        ['x-goog-api-key'] = api_key
      },
      body = vim.json.encode(
        {
          system_instruction = {parts = {text = instruction}},
          contents = (function()
            local contents = {}
            table.insert(contents, {role = 'user', parts = {{text = prompt}}})
            return contents
          end)(),
          safetySettings = {
            { category = 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold = 'BLOCK_NONE' },
            { category = 'HARM_CATEGORY_HATE_SPEECH',       threshold = 'BLOCK_NONE' },
            { category = 'HARM_CATEGORY_HARASSMENT',        threshold = 'BLOCK_NONE' },
            { category = 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold = 'BLOCK_NONE' }
          },
          generationConfig = {
            temperature = 0.2,
            topP = 0.5
          }
        }),
      callback = function(res)
        -- common.log("Before GoogleAI callback call")
        -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
      end
    })
end

return query

```

---

## `lua/ai/openai/query.lua`

We replaced `vim.fn.json_decode()` with `vim.json.decode()`.

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.formatResult(data, upload_url, upload_token, upload_as_public)
  common.log("Inside OpenAI formatResult")
  local prompt_tokens = data.usage.prompt_tokens or 0 -- Default to 0 for disabled model
  local completion_tokens = data.usage.completion_tokens or 0 -- Default to 0 for disabled model

  local formatted_prompt_tokens = string.format("%gk", math.floor(prompt_tokens / 1000))
  local formatted_completion_tokens = string.format("%gk", math.floor(completion_tokens / 1000))

  -- Create the result string with token counts
  local result = data.choices[1].message.content .. '\n\n' .. 'OpenAI ' .. modelUsed .. ' (' .. formatted_prompt_tokens .. ' in, ' .. formatted_completion_tokens .. ' out)\n\n'
  result = common.insertWordToTitle('OPN', result)
  history.saveToHistory('openai_' .. modelUsed , promptToSave .. '\n\n' .. result)

  -- START: Upload the formatted result with public option
  common.uploadContent(upload_url, upload_token, result, 'OpenAI (' .. modelUsed .. ')', upload_as_public)
  -- END: Upload the formatted result with public option

  return result
end

-- Added a new function to handle and format OpenAI API errors
function query.formatError(status, body)
  common.log("Formatting OpenAI API error: " .. body)
  local error_result
  -- Try to parse the error JSON
  local success, error_data = pcall(vim.json.decode, body)
  if success and error_data and error_data.error then
    -- Extract specific error information
    local error_type = error_data.error.type or "unknown_error"
    local error_message = error_data.error.message or "Unknown error occurred"
    local error_code = error_data.error.code or ""
    local error_param = error_data.error.param or ""
    -- Build error message with all available details
    error_result = string.format("# OpenAI API Error (%s)\n\n**Error Type**: %s\n", status, error_type)
    if error_code ~= "" then
      error_result = error_result .. string.format("**Error Code**: %s\n", error_code)
    end
    if error_param ~= "" then
      error_result = error_result .. string.format("**Parameter**: %s\n", error_param)
    end
    error_result = error_result .. string.format("**Message**: %s\n", error_message)
  else
    -- Fallback for unexpected error format
    error_result = string.format("# OpenAI API Error (%s)\n\n```\n%s\n```", status, body)
  end
  return error_result
end

query.askCallback = function(res, opts)
  local handleError = query.formatError  -- Set our custom error handler
  -- Modified: Pass upload_url, upload_token, and upload_as_public from opts to common.askCallback
  common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token, upload_as_public = opts.upload_as_public}, query.formatResult)
end

local disabled_response = {
  choices = { { message = { content = "OpenAI models are disabled" } } },
  usage = { prompt_tokens = 0, completion_tokens = 0 }
}

-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.askHeavy(model, instruction, prompt, opts, agent_host, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  -- Check if model is disabled
  if model == "disabled" then
    -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
    return
  end

  local url = agent_host .. '/openai'
  local project_context = aiconfig.listScannedFilesFromConfig()
  local body_chunks = {}
  table.insert(body_chunks, {system_instruction = instruction})
  table.insert(body_chunks, {role = 'user', content = "I need your help on this project."})
  for _, context in pairs(project_context) do
    if aiconfig.contentOf(context) ~= nil then
      table.insert(body_chunks, {role = 'model', content = "What is the content of `" .. context .. "` ?"})
      table.insert(body_chunks, {role = 'user',  content = "The content of `" .. context .. "` is :\n```\n" .. aiconfig.contentOf(context) .. "\n```"})
    end
  end
  table.insert(body_chunks, {role = 'model', content = "Then what do you want me to do with all that information?"})
  table.insert(body_chunks, {role = 'user', content = prompt})
  table.insert(body_chunks, {model_to_use = model})
  table.insert(body_chunks, {temperature = 0.2})
  table.insert(body_chunks, {top_p = 0.1})
  table.insert(body_chunks, {})

  local function sendNextRequest(i)
    if i > #body_chunks then
      return
    end

    local message = body_chunks[i]
    local body = vim.json.encode(message)

    curl.post(url,
      {
        headers = {['Content-type'] = 'application/json'},
        body = body,
        callback = function(res)
          if i == #body_chunks then
            -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
            vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
          else
            sendNextRequest(i + 1)
          end
        end
      })
  end
  sendNextRequest(1)
end

-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
    return
  end

  local api_host = 'https://api.openai.com'
  -- local api_host = 'https://eowloffrpvxwtqp.m.pipedream.net'
  local path = '/v1/chat/completions'
  curl.post(api_host .. path,
    {
      headers = {
        ['Content-type'] = 'application/json',
        ['Authorization'] = 'Bearer ' .. api_key
      },
      body = vim.json.encode(
        {
          model = model,
          messages = (function()
            local messages = {}
            if string.sub(model, 1, 2) == 'o1' then
              table.insert(messages, {role = 'user', content = instruction .. '\n' .. prompt})
            else
              table.insert(messages, { role = 'system', content = instruction })
              table.insert(messages, {role = 'user', content = prompt})
            end
            return messages
          end)()
        }
      ),
      callback = function(res)
        common.log("Before OpenAI callback call")
        -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
      end
    })
end

return query

```

---

## `lua/ai/anthropic/query.lua`

We replaced `vim.fn.json_decode()` with `vim.json.decode()`.

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.formatResult(data, upload_url, upload_token, upload_as_public)
  common.log("Inside Anthropic formatResult")
  local input_tokens = data.usage.input_tokens or 0
  local output_tokens = data.usage.output_tokens or 0

  local formatted_input_tokens = string.format("%gk", math.floor(input_tokens / 1000))
  local formatted_output_tokens = string.format("%gk", math.floor(output_tokens / 1000))

  -- Create the result string with token counts
  local result = data.content[1].text .. '\n\n' .. 'Anthropic '.. modelUsed .. ' (' .. formatted_input_tokens .. ' in, ' .. formatted_output_tokens .. ' out)\n\n'
  result = common.insertWordToTitle('ANT', result)
  history.saveToHistory('claude_' .. modelUsed , promptToSave .. '\n\n' .. result)

  -- START: Upload the formatted result with public option
  common.uploadContent(upload_url, upload_token, result, 'Anthropic (' .. modelUsed .. ')', upload_as_public)
  -- END: Upload the formatted result with public option

  return result
end

-- Added a new function to handle and format Anthropic API errors
function query.formatError(status, body)
  common.log("Formatting Anthropic API error: " .. body)
  local error_result
  -- Try to parse the error JSON
  local success, error_data = pcall(vim.json.decode, body)
  if success and error_data and error_data.error then
    -- Extract specific error information
    local error_type = error_data.error.type or "unknown_error"
    local error_message = error_data.error.message or "Unknown error occurred"
    error_result = string.format(
      "# Anthropic API Error (%s)\n\n**Error Type**: %s\n**Message**: %s\n",
      status,
      error_type,
      error_message
    )
  else
    -- Fallback for unexpected error format
    error_result = string.format("# Anthropic API Error (%s)\n\n```\n%s\n```", status, body)
  end
  return error_result
end

query.askCallback = function(res, opts)
  local handleError = query.formatError  -- Set our custom error handler
  -- Modified: Pass upload_url, upload_token, and upload_as_public from opts to common.askCallback
  common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token, upload_as_public = opts.upload_as_public}, query.formatResult)
end

local disabled_response = {
  content = { { text = "Anthropic models are disabled" } },
  usage = { input_tokens = 0, output_tokens = 0 }
}

-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.askHeavy(model, instruction, prompt, opts, agent_host, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
    return
  end

  local url = agent_host .. '/anthropic'
  local project_context = aiconfig.listScannedFilesFromConfig()
  local body_chunks = {}
  table.insert(body_chunks, {system_instruction = instruction})
  table.insert(body_chunks, {role = 'user', content = "I need your help on this project."})
  for _, context in pairs(project_context) do
    if aiconfig.contentOf(context) ~= nil then
      table.insert(body_chunks, {role = 'model', content = "What is the content of `" .. context .. "` ?"})
      table.insert(body_chunks, {role = 'user',  content = "The content of `" .. context .. "` is :\n```\n" .. aiconfig.contentOf(context) .. "\n```"})
    end
  end
  table.insert(body_chunks, {role = 'model', content = "Then what do you want me to do with all that information?"})
  table.insert(body_chunks, {role = 'user', content = prompt})
  table.insert(body_chunks, {model_to_use = model})
  table.insert(body_chunks, {temperature = 0.2})
  table.insert(body_chunks, {top_p = 0.1})
  table.insert(body_chunks, {})

  local function sendNextRequest(i)
    if i > #body_chunks then
      return
    end

    local message = body_chunks[i]
    local body = vim.json.encode(message)

    curl.post(url,
      {
        headers = {['Content-type'] = 'application/json'},
        body = body,
        callback = function(res)
          if i == #body_chunks then
            -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
            vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
          else
            sendNextRequest(i + 1)
          end
        end
      })
  end
  sendNextRequest(1)
end


-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
    return
  end

  local api_host = 'https://api.anthropic.com'
  -- local api_host = 'https://eowloffrpvxwtqp.m.pipedream.net'
  local path = '/v1/messages'
  curl.post(api_host .. path,
    {
      headers = {
        ['Content-type'] = 'application/json',
        ['x-api-key'] = api_key,
        ['anthropic-version'] = '2023-06-01'
      },
      body = vim.json.encode(
        {
          model = model,
          max_tokens = 8192,
          system= instruction,
          messages = (function()
            local messages = {}
            table.insert(messages, {role = 'user', content = prompt})
            return messages
          end)()
        }
      ),
      callback = function(res)
        common.log("Before Anthropic callback call")
        -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
      end
    })
end

return query

```

GoogleAI gemini-2.5-pro-preview-05-06 (18k in, 17k out)


