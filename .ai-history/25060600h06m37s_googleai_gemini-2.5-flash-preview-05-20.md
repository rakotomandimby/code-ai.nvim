# "code-ai.nvim" Code review june 2025

Review the code and tell me what you think.



# This is gemini-2.5-flash-preview-05-20 answer (16k in, 15k out)

I have reviewed the provided Lua files for your Neovim plugin.

Here's a summary of my findings and proposed changes:

### General Observations

*   **Code Structure and Readability**: The code is generally well-structured and readable, following common Lua conventions.
*   **New Features (Upload)**: The integration of the upload feature (`upload_url`, `upload_token`) seems correctly propagated through the `init.lua` and `query.lua` files to the `common.lua` module.
*   **Error Handling**: The addition of `formatError` functions in each `query.lua` file is a good improvement for providing more detailed error messages from the APIs.
*   **Configuration**: The use of `.ai-system-instructions.md` and `.ai-scanned-files` for project-specific configuration is a robust approach.
*   **History Management**: The history saving and cleanup logic in `history.lua` appears sound.

### Identified Issues and Proposed Improvements

1.  **Critical Bug in `askHeavy` functions (`anthropic/query.lua`, `googleai/query.lua`, `openai/query.lua`)**:
    *   **Issue**: The `askHeavy` functions currently iterate through `body_chunks` and send each chunk as a *separate* `curl.post` request. However, the `callback` logic is designed such that `query.askCallback` (which processes the LLM response) is only called for the *last* `curl.post` request in the sequence. This means the LLM agent is only receiving the last, incomplete chunk of the conversation (e.g., just the model parameters like `temperature`, `top_p`, and `model_to_use`), and *not* the system instructions, project context, or the actual prompt. This is a fundamental flaw that prevents the agent from receiving the necessary input.
    *   **Fix**: The `body_chunks` should be assembled into a *single* JSON object representing the complete request (including system instruction, messages array, and model parameters) and sent in *one* `curl.post` call.

2.  **Design Improvement for `M.handle` in `init.lua`**:
    *   **Issue**: The current logic in `M.handle` uses an "all or nothing" approach for `askHeavy` vs. `askLight`. If `number_of_files` is 0, or *any* of the agent hosts are not configured, *all* three models (Anthropic, GoogleAI, OpenAI) fall back to `askLight` mode. This might not be the desired behavior. It would be more flexible to use `askHeavy` for models where an agent is configured and files are present, and `askLight` for others, on a per-model basis.
    *   **Improvement**: Refactor `M.handle` to determine the appropriate query function (`askHeavy` or `askLight`) for each model independently based on its specific agent host configuration and the presence of scanned files.

3.  **Minor Improvement: Error Messages in `init.lua` `setup`**:
    *   **Issue**: The error messages `error('You need to set both anthropic_model and googleai_model and openai_model')` are slightly imprecise.
    *   **Improvement**: Make them more explicit, e.g., "You need to set anthropic_model, googleai_model, and openai_model."

4.  **Minor Improvement: Log File Path in `common.lua`**:
    *   **Observation**: The log file path `/tmp/aiconfig.log` is hardcoded. While functional, it's generally better practice to use Neovim's standard paths (e.g., `vim.fn.stdpath('cache')` or `vim.fn.stdpath('data')`) or make it configurable for better cross-platform compatibility and user control.
    *   **Suggestion**: Add a comment in the code suggesting this as a future improvement. (No code change will be made for this point as it's a minor suggestion).

---

Below are the complete file contents with the proposed changes.

### `lua/ai/aiconfig.lua`

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

return aiconfig
```

### `lua/ai/init.lua`

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
  upload_url = '',
  upload_token = '',
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
  local use_googleai_agent = M.opts.googleai_agent_host ~= ''
  local use_openai_agent = M.opts.openai_agent_host ~= ''

  local update = nil

  -- Display initial loading message, potentially with scanned files table
  local initial_content = M.fill(def.loading_tpl, args)
  if number_of_files > 0 then
    initial_content = initial_content .. aiconfig.listScannedFilesAsFormattedTable()
  end
  update = M.createPopup(initial_content, width - 8, height - 4)

  local prompt = M.fill(def.prompt_tpl, args)
  -- Get system instructions from file or fall back to command definition
  local instruction = aiconfig.getSystemInstructions()

  -- Determine which models to use (command-specific overrides global)
  local anthropic_model = def.anthropic_model or M.opts.anthropic_model
  local googleai_model = def.googleai_model or M.opts.googleai_model
  local openai_model = def.openai_model or M.opts.openai_model

  -- Prepare common options for all LLM queries, including upload details
  local common_query_opts = {
    upload_url = M.opts.upload_url,
    upload_token = M.opts.upload_token,
  }

  local function handleResult(output, output_key)
    args[output_key] = output
    args.output = (args.anthropic_output or '').. (args.googleai_output or '') .. (args.openai_output or '')
    update(M.fill(def.result_tpl or '${output}', args))
  end

  -- Callbacks for each model, passing upload options
  local askHandleResultAndCallbackAnthropic = {
    handleResult = function(output) return handleResult(output, 'anthropic_output') end,
    callback = function() end,
    upload_url = common_query_opts.upload_url,
    upload_token = common_query_opts.upload_token,
  }

  local askHandleResultAndCallbackGoogleAI = {
    handleResult = function(output) return handleResult(output, 'googleai_output') end,
    callback = function() end,
    upload_url = common_query_opts.upload_url,
    upload_token = common_query_opts.upload_token,
  }

  local askHandleResultAndCallbackOpenAI = {
    handleResult = function(output) return handleResult(output, 'openai_output') end,
    callback = function() end,
    upload_url = common_query_opts.upload_url,
    upload_token = common_query_opts.upload_token,
  }

  -- [[ START: Proposed change for per-model heavy/light mode selection ]]
  -- Determine and execute queries for each model independently
  if use_anthropic_agent and number_of_files > 0 then
    common.log("Using Anthropic agent (heavy mode)")
    anthropic.askHeavy(
      anthropic_model,
      instruction,
      prompt,
      askHandleResultAndCallbackAnthropic,
      M.opts.anthropic_agent_host,
      common_query_opts.upload_url,
      common_query_opts.upload_token
    )
  else
    common.log("Using Anthropic light mode")
    anthropic.askLight(
      anthropic_model,
      instruction,
      prompt,
      askHandleResultAndCallbackAnthropic,
      M.opts.anthropic_api_key,
      common_query_opts.upload_url,
      common_query_opts.upload_token
    )
  end

  if use_googleai_agent and number_of_files > 0 then
    common.log("Using GoogleAI agent (heavy mode)")
    googleai.askHeavy(
      googleai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackGoogleAI,
      M.opts.googleai_agent_host,
      common_query_opts.upload_url,
      common_query_opts.upload_token
    )
  else
    common.log("Using GoogleAI light mode")
    googleai.askLight(
      googleai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackGoogleAI,
      M.opts.googleai_api_key,
      common_query_opts.upload_url,
      common_query_opts.upload_token
    )
  end

  if use_openai_agent and number_of_files > 0 then
    common.log("Using OpenAI agent (heavy mode)")
    openai.askHeavy(
      openai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackOpenAI,
      M.opts.openai_agent_host,
      common_query_opts.upload_url,
      common_query_opts.upload_token
    )
  else
    common.log("Using OpenAI light mode")
    openai.askLight(
      openai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackOpenAI,
      M.opts.openai_api_key,
      common_query_opts.upload_url,
      common_query_opts.upload_token
    )
  end
  -- [[ END: Proposed change for per-model heavy/light mode selection ]]
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

  -- [[ START: Proposed change for clearer error messages ]]
  if M.opts.anthropic_model == '' or M.opts.googleai_model == '' or M.opts.openai_model == '' then
    error('You need to set anthropic_model, googleai_model, and openai_model in your setup.')
  end
  if M.opts.anthropic_api_key == '' or M.opts.googleai_api_key == '' or M.opts.openai_api_key == '' then
    error('You need to set anthropic_api_key, googleai_api_key, and openai_api_key in your setup.')
  end
  -- [[ END: Proposed change for clearer error messages ]]

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

### `lua/ai/googleai/query.lua`

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data, upload_url, upload_token)
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

      result = '\n# This is ' .. modelUsed .. ' answer (' .. formatted_prompt_tokens .. ' in, ' .. formatted_answer_tokens .. ' out)\n\n'
      result = result .. data['candidates'][1]['content']['parts'][1]['text'] .. '\n'
    end
  else
    result = '# There are ' .. candidates_number .. ' GoogleAI candidates\n'
    for i = 1, candidates_number do
      result = result .. '## GoogleAI Candidate number ' .. i .. '\n'
      result = result .. data['candidates'][i]['content']['parts'][1]['text'] .. '\n'
    end
  end
  history.saveToHistory('googleai_' .. modelUsed  , promptToSave .. '\n\n' .. result)

  -- Upload the formatted result
  common.uploadContent(upload_url, upload_token, result, 'GoogleAI (' .. modelUsed .. ')')

  return result
end

-- Added a new function to handle and format GoogleAI API errors
function query.formatError(status, body)
  common.log("Formatting GoogleAI API error: " .. body)
  local error_result
  -- Try to parse the error JSON
  local success, error_data = pcall(vim.fn.json_decode, body)
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
    local handleError = query.formatError
    -- Pass upload_url and upload_token from opts to common.askCallback
    common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token}, query.formatResult)
end

local disabled_response = {
  candidates = { { content = { parts = { { text = "GoogleAI models are disabled" } } }, finishReason = "STOP" } },
  usageMetadata = { promptTokenCount = 0, candidatesTokenCount = 0 }
}

-- [[ START: Proposed fix for askHeavy function ]]
function query.askHeavy(model, instruction, prompt, opts, agent_host, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  -- Check if model is disabled
  if model == "disabled" then
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
    return
  end

  local url = agent_host .. '/googleai'
  local project_context = aiconfig.listScannedFilesFromConfig()

  local messages = {}
  local request_body = {}

  -- Add system instruction
  request_body.system_instruction = instruction

  -- Add initial user message
  table.insert(messages, {role = 'user', content = "I need your help on this project."})

  -- Add project context
  for _, context in pairs(project_context) do
    local content = aiconfig.contentOf(context)
    if content ~= nil then
      table.insert(messages, {role = 'model', content = "What is the content of `" .. context .. "` ?"})
      table.insert(messages, {role = 'user',  content = "The content of `" .. context .. "` is :\n```\n" .. content .. "\n```"})
    end
  end

  -- Add final prompt
  table.insert(messages, {role = 'model', content = "Then what do you want me to do with all that information?"})
  table.insert(messages, {role = 'user', content = prompt})

  request_body.messages = messages
  request_body.model_to_use = model
  request_body.temperature = 0.2
  request_body.top_p = 0.5

  local body = vim.json.encode(request_body)

  curl.post(url,
    {
      headers = {['Content-type'] = 'application/json'},
      body = body,
      callback = function(res)
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
      end
    })
end
-- [[ END: Proposed fix for askHeavy function ]]

function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
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
      body = vim.fn.json_encode(
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
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
      end
    })
end

return query
```

### `lua/ai/openai/query.lua`

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data, upload_url, upload_token)
  common.log("Inside OpenAI formatResult")
  local prompt_tokens = data.usage.prompt_tokens or 0 -- Default to 0 for disabled model
  local completion_tokens = data.usage.completion_tokens or 0 -- Default to 0 for disabled model

  local formatted_prompt_tokens = string.format("%gk", math.floor(prompt_tokens / 1000))
  local formatted_completion_tokens = string.format("%gk", math.floor(completion_tokens / 1000))

  -- Create the result string with token counts
  local result = '\n# This is '.. modelUsed .. ' answer (' .. formatted_prompt_tokens .. ' in, ' .. formatted_completion_tokens .. ' out)\n\n'
  result = result .. data.choices[1].message.content .. '\n\n'
  history.saveToHistory('openai_' .. modelUsed , promptToSave .. '\n\n' .. result)

  -- Upload the formatted result
  common.uploadContent(upload_url, upload_token, result, 'OpenAI (' .. modelUsed .. ')')

  return result
end

-- Added a new function to handle and format OpenAI API errors
function query.formatError(status, body)
  common.log("Formatting OpenAI API error: " .. body)
  local error_result
  -- Try to parse the error JSON
  local success, error_data = pcall(vim.fn.json_decode, body)
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
  local handleError = query.formatError
  -- Pass upload_url and upload_token from opts to common.askCallback
  common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token}, query.formatResult)
end

local disabled_response = {
  choices = { { message = { content = "OpenAI models are disabled" } } },
  usage = { prompt_tokens = 0, completion_tokens = 0 }
}

-- [[ START: Proposed fix for askHeavy function ]]
function query.askHeavy(model, instruction, prompt, opts, agent_host, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  -- Check if model is disabled
  if model == "disabled" then
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
    return
  end

  local url = agent_host .. '/openai'
  local project_context = aiconfig.listScannedFilesFromConfig()

  local messages = {}
  local request_body = {}

  -- Add system instruction
  request_body.system_instruction = instruction

  -- Add initial user message
  table.insert(messages, {role = 'user', content = "I need your help on this project."})

  -- Add project context
  for _, context in pairs(project_context) do
    local content = aiconfig.contentOf(context)
    if content ~= nil then
      table.insert(messages, {role = 'model', content = "What is the content of `" .. context .. "` ?"})
      table.insert(messages, {role = 'user',  content = "The content of `" .. context .. "` is :\n```\n" .. content .. "\n```"})
    end
  end

  -- Add final prompt
  table.insert(messages, {role = 'model', content = "Then what do you want me to do with all that information?"})
  table.insert(messages, {role = 'user', content = prompt})

  request_body.messages = messages
  request_body.model_to_use = model
  request_body.temperature = 0.2
  request_body.top_p = 0.1

  local body = vim.json.encode(request_body)

  curl.post(url,
    {
      headers = {['Content-type'] = 'application/json'},
      body = body,
      callback = function(res)
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
      end
    })
end
-- [[ END: Proposed fix for askHeavy function ]]

function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
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
      body = vim.fn.json_encode(
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
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
      end
    })
end

return query
```

### `lua/ai/anthropic/query.lua`

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data, upload_url, upload_token)
  common.log("Inside Anthropic formatResult")
  local input_tokens = data.usage.input_tokens or 0
  local output_tokens = data.usage.output_tokens or 0

  local formatted_input_tokens = string.format("%gk", math.floor(input_tokens / 1000))
  local formatted_output_tokens = string.format("%gk", math.floor(output_tokens / 1000))

  -- Create the result string with token counts
  local result = '\n# This is '.. modelUsed .. ' answer (' .. formatted_input_tokens .. ' in, ' .. formatted_output_tokens .. ' out)\n\n'
  result = result .. data.content[1].text .. '\n\n'
  history.saveToHistory('claude_' .. modelUsed , promptToSave .. '\n\n' .. result)

  -- Upload the formatted result
  common.uploadContent(upload_url, upload_token, result, 'Anthropic (' .. modelUsed .. ')')

  return result
end

-- Added a new function to handle and format Anthropic API errors
function query.formatError(status, body)
  common.log("Formatting Anthropic API error: " .. body)
  local error_result
  -- Try to parse the error JSON
  local success, error_data = pcall(vim.fn.json_decode, body)
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
  local handleError = query.formatError
  -- Pass upload_url and upload_token from opts to common.askCallback
  common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token}, query.formatResult)
end

local disabled_response = {
  content = { { text = "Anthropic models are disabled" } },
  usage = { input_tokens = 0, output_tokens = 0 }
}

-- [[ START: Proposed fix for askHeavy function ]]
function query.askHeavy(model, instruction, prompt, opts, agent_host, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
    return
  end

  local url = agent_host .. '/anthropic'
  local project_context = aiconfig.listScannedFilesFromConfig()

  local messages = {}
  local request_body = {}

  -- Add system instruction
  request_body.system_instruction = instruction

  -- Add initial user message
  table.insert(messages, {role = 'user', content = "I need your help on this project."})

  -- Add project context
  for _, context in pairs(project_context) do
    local content = aiconfig.contentOf(context)
    if content ~= nil then
      table.insert(messages, {role = 'model', content = "What is the content of `" .. context .. "` ?"})
      table.insert(messages, {role = 'user',  content = "The content of `" .. context .. "` is :\n```\n" .. content .. "\n```"})
    end
  end

  -- Add final prompt
  table.insert(messages, {role = 'model', content = "Then what do you want me to do with all that information?"})
  table.insert(messages, {role = 'user', content = prompt})

  request_body.messages = messages
  request_body.model_to_use = model
  request_body.temperature = 0.2
  request_body.top_p = 0.1

  local body = vim.json.encode(request_body)

  curl.post(url,
    {
      headers = {['Content-type'] = 'application/json'},
      body = body,
      callback = function(res)
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
      end
    })
end
-- [[ END: Proposed fix for askHeavy function ]]


function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
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
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
      end
    })
end

return query
```

### `lua/ai/history.lua`

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
  local file = io.open(filePath, "w")
  common.log("Writing to history file: " .. filePath)
  if file then
    file:write(content)
    file:close()
    history.removeOldestHistoryFiles(15)
    return filePath
  else
    return nil
  end
end

-- list files in the '.ai-history' directory, ordered by filename
function history.listHistoryFiles()
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  local files = vim.fn.readdir(historyDir)
  -- `vim.fn.readdir` returns files in arbitrary order.
  -- `table.sort` without a custom comparator will sort alphabetically.
  -- For filenames like `24061510h30m00s_model.md`, alphabetical sorting
  -- will correctly sort by date/time (oldest first).
  table.sort(files)
  for i, file in ipairs(files) do
    common.log("File " .. i .. ": " .. file)
  end
  return files
end

-- This function correctly removes the oldest files.
-- `history.listHistoryFiles()` sorts files by name ascending, which for the
-- `YYMMDDhhmmss` format means oldest files come first.
-- The loop `for i = #files - (numberOfFilesToKeep -1), 1, -1 do`
-- correctly identifies the files to delete from the beginning of the sorted list.
function history.removeOldestHistoryFiles(numberOfFilesToKeep)
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  local files = history.listHistoryFiles()
  common.log("Files in history folder:")
  for i, file in ipairs(files) do
    common.log("File " .. i .. ": " .. file)
  end
  if #files >  numberOfFilesToKeep then
    common.log(string.format("There are %d files in the history folder", #files))
    common.log(string.format("We need to remove %d files", #files - numberOfFilesToKeep))
    -- Loop from the index of the first file to remove down to 1.
    -- If #files = 20 and numberOfFilesToKeep = 15, we need to remove 5 files.
    -- The files to remove are files[1] through files[5].
    -- The loop should go from `i = 5` down to `1`.
    -- The current start index `(#files - (numberOfFilesToKeep - 1))` evaluates to `20 - (15 - 1) = 20 - 14 = 6`.
    -- This means it deletes files[6], files[5], ..., files[1]. This is correct.
    for i = #files - numberOfFilesToKeep, 1, -1 do
      local file = files[i]
      local filePath = historyDir .. '/' .. file
      vim.fn.delete(filePath)
      common.log("Deleted oldest history file: " .. filePath)
    end
  else
    common.log("There are less than ".. numberOfFilesToKeep .. " files in the history folder")
  end
end

return history
```

### `lua/ai/globpattern.lua`

```lua
local M = {}

function M.globtopattern(g)
  -- Some useful references:
  -- - apr_fnmatch in Apache APR.  For example,
  --   http://apr.apache.org/docs/apr/1.3/group__apr__fnmatch.html
  --   which cites POSIX 1003.2-1992, section B.6.

  local p = "^"  -- pattern being built
  local i = 0    -- index in g
  local c        -- char at index i in g.

  -- unescape glob char
  local function unescape()
    if c == '\\' then
      i = i + 1; c = g:sub(i,i)
      if c == '' then
        p = '[^]'
        return false
      end
    end
    return true
  end

  -- escape pattern char
  local function escape(c)
    return c:match("^%w$") and c or '%' .. c
  end

  -- Convert tokens at end of charset.
  local function charset_end()
    while 1 do
      if c == '' then
        p = '[^]'
        return false
      elseif c == ']' then
        p = p .. ']'
        break
      else
        if not unescape() then break end
        local c1 = c
        i = i + 1; c = g:sub(i,i)
        if c == '' then
          p = '[^]'
          return false
        elseif c == '-' then
          i = i + 1; c = g:sub(i,i)
          if c == '' then
            p = '[^]'
            return false
          elseif c == ']' then
            p = p .. escape(c1) .. '%-]'
            break
          else
            if not unescape() then break end
            p = p .. escape(c1) .. '-' .. escape(c)
          end
        elseif c == ']' then
          p = p .. escape(c1) .. ']'
          break
        else
          p = p .. escape(c1)
          i = i - 1 -- put back
        end
      end
      i = i + 1; c = g:sub(i,i)
    end
    return true
  end

  -- Convert tokens in charset.
  local function charset()
    i = i + 1; c = g:sub(i,i)
    if c == '' or c == ']' then
      p = '[^]'
      return false
    elseif c == '^' or c == '!' then
      i = i + 1; c = g:sub(i,i)
      if c == ']' then
        -- ignored
      else
        p = p .. '[^'
        if not charset_end() then return false end
      end
    else
      p = p .. '['
      if not charset_end() then return false end
    end
    return true
  end

  -- Convert tokens.
  while 1 do
    i = i + 1; c = g:sub(i,i)
    if c == '' then
      p = p .. '$'
      break
    elseif c == '?' then
      p = p .. '.'
    elseif c == '*' then
      p = p .. '.*'
    elseif c == '[' then
      if not charset() then break end
    elseif c == '\\' then
      i = i + 1; c = g:sub(i,i)
      if c == '' then
        p = p .. '\\$'
        break
      end
      p = p .. escape(c)
    else
      p = p .. escape(c)
    end
  end
  return p
end

return M
```

### `lua/ai/common.lua`

```lua
local common = {}
local curl = require('plenary.curl')

function common.log(message)
  -- The log file path is currently hardcoded to /tmp/aiconfig.log.
  -- For better cross-platform compatibility and adherence to Neovim's standard
  -- directory structure, consider making this configurable or using
  -- vim.fn.stdpath('cache') or vim.fn.stdpath('data').
  local log_file = io.open("/tmp/aiconfig.log", "a")
  if not log_file then
    error("Could not open log file for writing.")
  end
  -- build a timestamp string surrounded by [] that will prepend the log message
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  message = "[ " .. timestamp .. " ] -- " .. message
  log_file:write(message .. "\n")
  log_file:close()
end

function common.uploadContent(url, token, content, model_name)
  if url == '' or token == '' then
    common.log("Upload URL or Token not configured. Skipping upload for " .. model_name .. " response.")
    return
  end

  common.log("Attempting to upload " .. model_name .. " response to: " .. url)

  local headers = {
    ['Content-Type'] = 'text/markdown',
    ['X-MarkdownBlog-Token'] = token
  }

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
    -- Pass upload_url and upload_token to formatResult
    result = formatResult(data, opts.upload_url, opts.upload_token)
    if opts.handleResult ~= nil then
      result = opts.handleResult(result)
    end
  end
  opts.callback(result)
end
return common
```
