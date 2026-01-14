local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data, upload_url, upload_token, upload_as_public)
  common.log("Inside Github formatResult")

  local function collect_texts(d)
    local out = {}

    -- Handle choices array from Github Models API
    if type(d.choices) == 'table' and #d.choices > 0 then
      for _, choice in ipairs(d.choices) do
        if type(choice.message) == 'table' then
          local content = choice.message.content
          if type(content) == 'string' and content ~= '' then
            table.insert(out, content)
          end
        end
      end
    end

    return out
  end

  local prompt_tokens = 0
  local completion_tokens = 0

  -- Github Models API usage structure
  if type(data.usage) == 'table' then
    prompt_tokens = data.usage.prompt_tokens or 0
    completion_tokens = data.usage.completion_tokens or 0
  end

  local formatted_prompt_tokens = common.formatTokenCount(prompt_tokens)
  local formatted_completion_tokens = common.formatTokenCount(completion_tokens)

  local pieces = collect_texts(data)
  local text = table.concat(pieces, "\n\n")

  local result = text
    .. '\n\n'
    .. 'Github ' .. modelUsed
    .. ' (' .. formatted_prompt_tokens .. ' in, ' .. formatted_completion_tokens .. ' out)\n\n'

  result = common.insertWordToTitle('GHB', result)

  -- For disabled models, do not write history nor upload.
  if modelUsed ~= 'disabled' then
    history.saveToHistory('github_' .. modelUsed, promptToSave .. '\n\n' .. result)
    local model_label = 'Github (' .. modelUsed .. ')'
    common.uploadContent(upload_url, upload_token, result, model_label, upload_as_public)
  else
    common.log("Github model is disabled: skipping history save and upload.")
  end

  return result
end

function query.formatError(status, body)
  common.log("Formatting Github API error: " .. body)
  local error_result
  local success, error_data = pcall(vim.fn.json_decode, body)

  if success and error_data and error_data.error then
    local error_message = error_data.error.message or "Unknown error occurred"
    local error_type = error_data.error.type or "unknown_error"
    local error_code = error_data.error.code or ""

    error_result = string.format("# Github API Error (%s)\n\n**Error Type**: %s\n", status, error_type)
    if error_code ~= "" then
      error_result = error_result .. string.format("**Error Code**: %s\n", error_code)
    end
    error_result = error_result .. string.format("**Message**: %s\n", error_message)
  else
    error_result = string.format("# Github API Error (%s)\n\n```\n%s\n```", status, body)
  end
  return error_result
end

query.askCallback = function(res, opts)
  local handleError = query.formatError
  common.askCallback(
    res,
    {
      handleResult = opts.handleResult,
      handleError = handleError,
      callback = opts.callback,
      upload_url = opts.upload_url,
      upload_token = opts.upload_token,
      upload_as_public = opts.upload_as_public
    },
    query.formatResult
  )
end

local disabled_response = {
  choices = {
    { message = { role = "assistant", content = "Github models are disabled" } }
  },
  usage = {
    prompt_tokens = 0,
    completion_tokens = 0,
    total_tokens = 0,
  },
}

function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    common.handleDisabledModel('Github', model,
      {
        handleResult = opts.handleResult,
        callback = opts.callback,
        upload_url = upload_url,
        upload_token = upload_token,
        upload_as_public = upload_as_public
      },
      query.askCallback,
      disabled_response
    )
    return
  end

  local scanned_files = aiconfig.listScannedFilesFromConfig()
  local project_context = {}

  for _, context in pairs(scanned_files) do
    local content = aiconfig.contentOf(context)
    if content ~= nil then
      table.insert(project_context, {filename = context, content = content})
    end
  end

  common.askHeavy(
    agent_host,
    api_key,
    model,
    instruction,
    prompt,
    project_context,
    {
      handleResult = opts.handleResult,
      callback = opts.callback,
      upload_url = upload_url,
      upload_token = upload_token,
      upload_as_public = upload_as_public
    },
    query.askCallback
  )
end

function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    common.handleDisabledModel('Github', model,
      {
        handleResult = opts.handleResult,
        callback = opts.callback,
        upload_url = upload_url,
        upload_token = upload_token,
        upload_as_public = upload_as_public
      },
      query.askCallback,
      disabled_response
    )
    return
  end

  local api_host = 'https://models.github.ai'
  local path = '/inference/chat/completions'

  local messages = {}

  -- Add system message only if instruction is provided and not empty
  if instruction and instruction ~= '' then
    table.insert(messages, {
      role = 'system',
      content = instruction
    })
  else
    common.log("Github Light mode: No system instructions provided")
  end

  -- Add user message
  table.insert(messages, {
    role = 'user',
    content = prompt
  })

  curl.post(api_host .. path, {
    headers = {
      ['Accept'] = 'application/vnd.github+json',
      ['Authorization'] = 'Bearer ' .. api_key,
      ['X-GitHub-Api-Version'] = '2022-11-28',
      ['Content-Type'] = 'application/json',
    },
    body = vim.fn.json_encode({
      model = model,
      messages = messages,
    }),
    callback = function(res)
      common.log("Before Github callback call (Chat Completions API)")
      vim.schedule(function()
        query.askCallback(res, {
          handleResult = opts.handleResult,
          callback = opts.callback,
          upload_url = upload_url,
          upload_token = upload_token,
          upload_as_public = upload_as_public
        })
      end)
    end
  })
end

return query

