# Having system instruction in a `.ai-system-instructions.md` file.

Currently, system instructions are given in command definition.

I want to change that: I want to have a `.ai-system-instructions.md` file that contains all the system instructions.

The system instructions file will be located in the same directory as the `.ai-prompts.md` file.

We will have to remove givin the system instructions in the command definition.

Tell me the modifications I have to make to the code in order to implement this feature.




# This is gemini-2.0-pro-exp answer (10k in, 8k out)

Okay, let's outline the modifications needed to implement the `.ai-system-instructions.md` feature, moving the system instructions from the command definitions within `lua/ai/init.lua` to a dedicated file.

Here's a breakdown of the changes and the reasoning behind them:

**1. `lua/ai/aiconfig.lua` (New Function):**

We'll add a function to `aiconfig.lua` to locate and read the `.ai-system-instructions.md` file. This keeps the configuration-related logic centralized.

```lua
-- In lua/ai/aiconfig.lua

function aiconfig.getSystemInstructions()
  local project_root = aiconfig.getProjectRoot()
  local instructions_file = project_root .. "/.ai-system-instructions.md"
  local file = io.open(instructions_file, "r")

  if file then
    local content = file:read("*all")
    file:close()
    return content
  else
    return ""  -- Or return a default instruction, or throw an error.
  end
end
```

**2. `lua/ai/init.lua` (Modifications):**

   *   **Remove `instruction_tpl` from `default_prompts`:**  We no longer need to define instructions within each prompt definition.
   *   **Load System Instructions:**  Inside the `M.handle` function, we'll call the new `aiconfig.getSystemInstructions()` function to retrieve the instructions.
   *   **Pass Instructions to `ask` and `askHeavy`:** The `instruction` parameter will be passed to the `ask` and `askHeavy` functions of `anthropic`, `gemini`, and `chatgpt`.
   *   **Remove instruction from default prompts:** Remove the `instruction_tpl` from the `default_prompts` table.

```lua
-- In lua/ai/init.lua

local default_prompts = {
  introduce = {
    command = 'AIIntroduceYourself',
    loading_tpl = 'Loading...',
    prompt_tpl = 'Say who you are, your version, and the currently used model',
    -- instruction_tpl = 'Act as a command line command that has been issued with the --help flag',  -- REMOVE THIS
    result_tpl = '${output}',
    require_input = false,
  }
}

-- ... (rest of the file) ...

function M.handle(name, input)
  -- ... (existing code) ...

  local prompt = M.fill(def.prompt_tpl, args)
  -- local instruction = M.fill(def.instruction_tpl, args) -- REMOVE THIS LINE
  local instruction = aiconfig.getSystemInstructions() -- ADD THIS LINE

  -- ... (rest of the function) ...
end
```

**3. `lua/ai/anthropic/query.lua`, `lua/ai/gemini/query.lua`, and `lua/ai/chatgpt/query.lua` (Modifications):**

The `ask` and `askHeavy` functions in each of these files need to be modified to correctly use the `system_instruction` that is now read from the file.

*   **`lua/ai/anthropic/query.lua`:**

    ```lua
    -- In lua/ai/anthropic/query.lua

    function query.askHeavy(model, instruction, prompt, opts, agent_host)
      -- ... (existing code) ...
      table.insert(body_chunks, {system_instruction = instruction}) -- This line already exists, keep it.
      -- ... (rest of the function) ...
    end

    function query.ask(model, instruction, prompt, opts, api_key)
      -- ... (existing code) ...
      body = vim.fn.json_encode(
        {
          model = model,
          max_tokens = 8192,
          system= instruction,  -- This line already exists, keep it.
          messages = (function()
            local messages = {}
            table.insert(messages, {role = 'user', content = prompt})
            return messages
          end)()
        }
      ),
      -- ... (rest of the function) ...
    end
    ```

*   **`lua/ai/gemini/query.lua`:**

    ```lua
    -- In lua/ai/gemini/query.lua

    function query.askHeavy(model, instruction, prompt, opts, agent_host)
      -- ... (existing code) ...
      table.insert(body_chunks, {system_instruction = instruction}) -- This line already exists, keep it.
      -- ... (rest of the function) ...
    end

    function query.ask(model, instruction, prompt, opts, api_key)
      -- ... (existing code) ...
      body = vim.fn.json_encode(
        {
          system_instruction = {parts = {text = instruction}}, -- This line already exists, keep it.
          contents = (function()
            local contents = {}
            table.insert(contents, {role = 'user', parts = {{text = prompt}}})
            return contents
          end)(),
          -- ... (rest of the function) ...
        }
      ),
      -- ... (rest of the function) ...
    end
    ```

*   **`lua/ai/chatgpt/query.lua`:**

    ```lua
    -- In lua/ai/chatgpt/query.lua

    function query.askHeavy(model, instruction, prompt, opts, agent_host)
      -- ... (existing code) ...
      table.insert(body_chunks, {system_instruction = instruction}) -- This line already exists, keep it.
      -- ... (rest of the function) ...
    end

    function query.ask(model, instruction, prompt, opts, api_key)
      -- ... (existing code) ...
      body = vim.fn.json_encode(
        {
          model = model,
          messages = (function()
            local messages = {}
            if string.sub(model, 1, 2) == 'o1' then
              table.insert(messages, {role = 'user', content = instruction .. '\n' .. prompt})
            else
              table.insert(messages, { role = 'system', content = instruction }) -- This line already exists, keep it.
              table.insert(messages, {role = 'user', content = prompt})
            end
            return messages
          end)()
        }
      ),
      -- ... (rest of the function) ...
    end
    ```

**Complete Files (After Changes):**

*   **`lua/ai/aiconfig.lua`:**

```lua
local aiconfig = {}

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
    return {}
  end

  local include_patterns = {}
  local exclude_patterns = {}

  -- Read the config file and separate include and exclude patterns
  for line in io.lines(config) do
    local trimmed_line = vim.trim(line)
    if vim.startswith(trimmed_line, "+") then
      table.insert(include_patterns, trimmed_line:sub(2)) -- Remove the '+' and add to include patterns
    elseif vim.startswith(trimmed_line, "-") then
      table.insert(exclude_patterns, trimmed_line:sub(2)) -- Remove the '-' and add to exclude patterns
    end
  end

  -- Step 1: Gather all files that match the include patterns
  local included_files = {}
  for _, pattern in ipairs(include_patterns) do
    for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
      included_files[file] = true -- Use a table to avoid duplicates
    end
  end

  -- Step 2: Remove files that match the exclude patterns
  for _, pattern in ipairs(exclude_patterns) do
    for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
      included_files[file] = nil -- Remove excluded files
    end
  end

  -- Step 3: Convert the table back to a list
  local final_files = {}
  for file, _ in pairs(included_files) do
    local file_info = vim.loop.fs_stat(file)
    if file_info and file_info.type == 'file' then
      table.insert(final_files, file)
    end
  end

  -- Sort final_files before returning it
  table.sort(final_files)
  return final_files
end

function aiconfig.listScannedFilesAsText()
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
  if #analyzed_files_as_array == 0 then
    return "# No files to analyze under project root " .. aiconfig.getProjectRoot()
  end

  local analyzed_files_as_string = " will be analyzed under project root ".. aiconfig.getProjectRoot() .. ":\n"
  local total_size = 0 -- Initialize total size

  for _, file in ipairs(analyzed_files_as_array) do
    local stat = vim.loop.fs_stat(file)
    local size = stat and stat.size or 0 -- Default to 0 if size is unknown
    total_size = total_size + size -- Add file size to total

    local size_str = size .. " B"
    if size > 1024 then
      size_str = string.format("%.2f KB", size / 1024)
    end
    if size > 1024 * 1024 then
      size_str = string.format("%.2f MB", size / (1024 * 1024))
    end
    analyzed_files_as_string = analyzed_files_as_string .. "- " .. file .. " (Size: " .. size_str .. ")\n"
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

function aiconfig.getSystemInstructions()
  local project_root = aiconfig.getProjectRoot()
  local instructions_file = project_root .. "/.ai-system-instructions.md"
  local file = io.open(instructions_file, "r")

  if file then
    local content = file:read("*all")
    file:close()
    return content
  else
    return ""  -- Or return a default instruction, or throw an error.
  end
end

return aiconfig
```

*   **`lua/ai/init.lua`:**

```lua
local anthropic = require('ai.anthropic.query')
local gemini = require('ai.gemini.query')
local chatgpt = require('ai.chatgpt.query')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')

local default_prompts = {
  introduce = {
    command = 'AIIntroduceYourself',
    loading_tpl = 'Loading...',
    prompt_tpl = 'Say who you are, your version, and the currently used model',
    -- instruction_tpl = 'Act as a command line command that has been issued with the --help flag',  -- REMOVE THIS
    result_tpl = '${output}',
    require_input = false,
  }
}

local M = {}
M.opts = {
  anthropic_model = '',
  gemini_model = '',
  chatgpt_model = '',

  anthropic_agent_host = '',
  gemini_agent_host = '',
  chatgpt_agent_host = '',

  anthropic_api_key = '',
  gemini_api_key = '',
  chatgpt_api_key = '',

  locale = 'en',
  alternate_locale = 'fr',
  result_popup_gets_focus = false,
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
  local use_gemini_agent = M.opts.gemini_agent_host ~= ''
  local use_chatgpt_agent = M.opts.chatgpt_agent_host ~= ''

  local update = nil

  if (number_of_files == 0 or not use_anthropic_agent or not use_gemini_agent or not use_chatgpt_agent ) then
    update = M.createPopup(M.fill(def.loading_tpl , args), width - 8, height - 4)
  else
    local scanned_files = aiconfig.listScannedFiles()
    update = M.createPopup(M.fill(def.loading_tpl .. scanned_files, args), width - 8, height - 4)
  end
  local prompt = M.fill(def.prompt_tpl, args)
  -- local instruction = M.fill(def.instruction_tpl, args) -- REMOVE THIS LINE
  local instruction = aiconfig.getSystemInstructions() -- ADD THIS LINE

  -- Determine which models to use
  local anthropic_model = def.anthropic_model or M.opts.anthropic_model
  local gemini_model = def.gemini_model or M.opts.gemini_model
  local chatgpt_model = def.chatgpt_model or M.opts.chatgpt_model

  -- If command-level models are set, use them
  if def.anthropic_model and def.anthropic_model ~= '' then
    anthropic_model = def.anthropic_model
  end
  if def.gemini_model and def.gemini_model ~= '' then
    gemini_model = def.gemini_model
  end
  if def.chatgpt_model and def.chatgpt_model ~= '' then
    chatgpt_model = def.chatgpt_model
  end


  local function handleResult(output, output_key)
    args[output_key] = output
    args.output = (args.anthropic_output or '')..(args.gemini_output or '') .. (args.chatgpt_output or '')
    update(M.fill(def.result_tpl or '${output}', args))
  end

  local askHandleResultAndCallbackAnthropic = {
    handleResult = function(output) return handleResult(output, 'anthropic_output') end,
    callback = function() end
  }

  local askHandleResultAndCallbackGemini = {
    handleResult = function(output) return handleResult(output, 'gemini_output') end,
    callback = function() end
  }

  local askHandleResultAndCallbackChatGPT = {
    handleResult = function(output) return handleResult(output, 'chatgpt_output') end,
    callback = function() end
  }

  if (number_of_files == 0
        or not use_anthropic_agent
        or not use_gemini_agent
        or not use_chatgpt_agent) then
    common.log("Not using agents")
    anthropic.ask(
      anthropic_model,
      instruction,
      prompt,
      askHandleResultAndCallbackAnthropic,
      M.opts.anthropic_api_key)
    gemini.ask(
      gemini_model,
      instruction,
      prompt,
      askHandleResultAndCallbackGemini,
      M.opts.gemini_api_key)
    chatgpt.ask(
      chatgpt_model,
      instruction,
      prompt,
      askHandleResultAndCallbackChatGPT,
      M.opts.chatgpt_api_key)
  else
    common.log("Using agents")
    anthropic.askHeavy(
      anthropic_model,
      instruction,
      prompt,
      askHandleResultAndCallbackAnthropic,
      M.opts.anthropic_agent_host)
    gemini.askHeavy(
      gemini_model,
      instruction,
      prompt,
      askHandleResultAndCallbackGemini,
      M.opts.gemini_agent_host)
    chatgpt.askHeavy(
      chatgpt_model,
      instruction,
      prompt,
      askHandleResultAndCallbackChatGPT,
      M.opts.chatgpt_agent_host)
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

  if M.opts.anthropic_model == '' or  M.opts.gemini_model == '' or M.opts.chatgpt_model == '' then
    error('You need to set both anthropic_model and gemini_model and chatgpt_model')
  end
  if M.opts.anthropic_api_key ==''or M.opts.gemini_api_key == '' or M.opts.chatgpt_api_key == '' then
    error('You need to set both anthropic_api_key and gemini_api_key and chatgpt_api_key')
  end

  vim.api.nvim_create_user_command('AIListScannedFiles', function()
    local width = vim.fn.winwidth(0)
    local height = vim.fn.winheight(0)
    local scanned_files = aiconfig.listScannedFiles()
    local update = M.createPopup(scanned_files, width - 12, height - 8)
    update(scanned_files)
  end, {})
end

vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  callback = M.close,
})

return M
```

*   **`lua/ai/anthropic/query.lua`:** (No changes needed, already correct)

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data)
  common.log("Inside Anthropic formatResult")
  local input_tokens = data.usage.input_tokens
  local output_tokens = data.usage.output_tokens

  local formatted_input_tokens = string.format("%gk", math.floor(input_tokens / 1000))
  local formatted_output_tokens = string.format("%gk", math.floor(output_tokens / 1000))

  -- Create the result string with token counts
  local result = '\n# This is '.. modelUsed .. ' answer (' .. formatted_input_tokens .. ' in, ' .. formatted_output_tokens .. ' out)\n\n'
  result = result .. data.content[1].text .. '\n\n'
  history.saveToHistory('claude_' .. modelUsed , promptToSave .. '\n\n' .. result)
  return result
end

query.askCallback = function(res, opts)
  common.askCallback(res, opts, query.formatResult)
end

function query.askHeavy(model, instruction, prompt, opts, agent_host)
  promptToSave = prompt
  modelUsed = model
  local url = agent_host .. '/anthropic'
  local project_context = aiconfig.listScannedFilesFromConfig()
  local body_chunks = {}
  table.insert(body_chunks, {system_instruction = instruction})
  table.insert(body_chunks, {role = 'user', content = "I need your help on this project."})
  table.insert(body_chunks, {role = 'model', content = "Tell me the project file structure."})
  table.insert(body_chunks, {role = 'user',  content = aiconfig.listScannedFilesAsText()})
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
            vim.schedule(function() query.askCallback(res, opts) end)
          else
            sendNextRequest(i + 1)
          end
        end
      })
  end

  sendNextRequest(1)

end


function query.ask(model, instruction, prompt, opts, api_key)
  promptToSave = prompt
  modelUsed = model
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
      body = vim.fn.json_encode(
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
        vim.schedule(function() query.askCallback(res, opts) end)
      end
    })
end

return query
```

*   **`lua/ai/gemini/query.lua`:** (No changes needed, already correct)

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data)
  common.log("Inside Gemini formatResult")
  local result = ''
  local candidates_number = #data['candidates']
  if candidates_number == 1 then
    if data['candidates'][1]['content'] == nil then
      result = '\n#Gemini error\n\nGemini stopped with the reason: ' .. data['candidates'][1]['finishReason'] .. '\n'
      return result
    else
      -- Extract token counts from the response
      local prompt_tokens = data['usageMetadata']['promptTokenCount']
      local answer_tokens = data['usageMetadata']['candidatesTokenCount']

      -- Format token counts (e.g., "30k", "2k")
      local formatted_prompt_tokens = string.format("%gk", math.floor(prompt_tokens / 1000))
      local formatted_answer_tokens = string.format("%gk", math.floor(answer_tokens / 1000))

      result = '\n# This is ' .. modelUsed .. ' answer (' .. formatted_prompt_tokens .. ' in, ' .. formatted_answer_tokens .. ' out)\n\n'
      result = result .. data['candidates'][1]['content']['parts'][1]['text'] .. '\n'
    end
  else
    result = '# There are ' .. candidates_number .. ' Gemini candidates\n'
    for i = 1, candidates_number do
      result = result .. '## Gemini Candidate number ' .. i .. '\n'
      result = result .. data['candidates'][i]['content']['parts'][1]['text'] .. '\n'
    end
  end
  history.saveToHistory('gemini_' .. modelUsed  , promptToSave .. '\n\n' .. result)
  return result
end

query.askCallback = function(res, opts)
    common.askCallback(res, opts, query.formatResult)
end

function query.askHeavy(model, instruction, prompt, opts, agent_host)
  promptToSave = prompt
  modelUsed = model
  local url = agent_host .. '/gemini'
  local project_context = aiconfig.listScannedFilesFromConfig()
  local body_chunks
