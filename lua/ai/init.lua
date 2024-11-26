local gemini = require('ai.gemini.query')
local chatgpt = require('ai.chatgpt.query')
local aiconfig = require('ai.aiconfig')

local default_prompts = {
  introduce = {
    command = 'AIIntroduceYourself',
    loading_tpl = 'Loading...',
    prompt_tpl = 'Say who you are, your version, and the currently used model',
    instruction_tpl = 'Act as a command line command that has been issued with the --help flag',
    result_tpl = '${output}',
    require_input = false,
  }
}

local M = {}
M.opts = {
  gemini_agent_host = '',
  chatgpt_agent_host = '',
  gemini_api_key = '',
  chatgpt_api_key = '',
  locale = 'en',
  alternate_locale = 'fr',
  result_popup_gets_focus = false,
}
M.prompts = default_prompts
local win_id

function M.log(message)
  local log_file = io.open("/tmp/aiconfig.log", "a")
  if not log_file then
    error("Could not open log file for writing.")
  end
  -- prepend timestamp to message
  message = os.date("%Y-%m-%d %H:%M:%S") .. " " .. message
  log_file:write(message .. "\n\n")
  log_file:close()
end

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
  local scanned_files = aiconfig.listScannedFiles()
  local update = M.createPopup(M.fill(def.loading_tpl .. scanned_files, args), width - 12, height - 8)
  local prompt = M.fill(def.prompt_tpl, args)
  local instruction = M.fill(def.instruction_tpl, args)

  local function handleResult(output, output_key)
    args[output_key] = output
    args.output = (args.gemini_output or '') .. (args.chatgpt_output or '')
    update(M.fill(def.result_tpl or '${output}', args)) -- Update the popup directly
  end
  local number_of_files = #aiconfig.listScannedFilesFromConfig()

  -- If M.opts.gemini_agent_host is not set, set it to an empty string
  if M.opts.gemini_agent_host == nil then
    M.opts.gemini_agent_host = ''
  end


  if M.opts.chatgpt_agent_host == nil then
    M.opts.chatgpt_agent_host = ''
  end

  M.log("Gemini agent URL is " .. M.opts.gemini_agent_host " and ChatGPT agent URL is " .. M.opts.chatgpt_agent_host " and number of files is " .. number_of_files)
  if ((M.opts.gemini_agent_host == '' or M.opts.chatgpt_agent_host == '') or number_of_files == 0) then
    M.log("Not using agents")
    gemini.ask(instruction, prompt,{handleResult = function(gemini_output)  return handleResult(gemini_output,  'gemini_output')  end,callback = function() end},M.opts.gemini_api_key)
    chatgpt.ask(instruction,prompt,{handleResult = function(chatgpt_output) return handleResult(chatgpt_output, 'chatgpt_output') end,callback = function() end},M.opts.chatgpt_api_key)
  else
    M.log("Using agents")
    gemini.askHeavy(instruction,prompt, {handleResult = function(gemini_output)  return handleResult(gemini_output,  'gemini_output')  end,callback = function() end},M.opts.gemini_agent_host)
    chatgpt.askHeavy(instruction,prompt,{handleResult = function(chatgpt_output) return handleResult(chatgpt_output, 'chatgpt_output') end,callback = function() end},M.opts.chatgpt_agent_host)
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
