local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data, upload_url, upload_token, upload_as_public)
  common.log("Inside Anthropic formatResult")
  
  local input_tokens = data.usage.input_tokens or 0
  local output_tokens = data.usage.output_tokens or 0

  local formatted_input_tokens = common.formatTokenCount(input_tokens)
  local formatted_output_tokens = common.formatTokenCount(output_tokens)

  local result = data.content[1].text 
    .. '\n\n' 
    .. 'Anthropic ' .. modelUsed 
    .. ' (' .. formatted_input_tokens .. ' in, ' .. formatted_output_tokens .. ' out)\n\n'
  
  result = common.insertWordToTitle('ANT', result)
  history.saveToHistory('anthropic_' .. modelUsed, promptToSave .. '\n\n' .. result)

  common.uploadContent(upload_url, upload_token, result, 'Anthropic (' .. modelUsed .. ')', upload_as_public)

  return result
end

function query.formatError(status, body)
  common.log("Formatting Anthropic API error: " .. body)
  local error_result
  local success, error_data = pcall(vim.fn.json_decode, body)
  
  if success and error_data and error_data.error then
    local error_type = error_data.error.type or "unknown_error"
    local error_message = error_data.error.message or "Unknown error occurred"
    error_result = string.format(
      "# Anthropic API Error (%s)\n\n**Error Type**: %s\n**Message**: %s\n",
      status,
      error_type,
      error_message
    )
  else
    error_result = string.format("# Anthropic API Error (%s)\n\n```\n%s\n```", status, body)
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
  content = { { text = "Anthropic models are disabled" } },
  usage = { input_tokens = 0, output_tokens = 0 }
}

function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    common.handleDisabledModel('Anthropic', model, 
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
    common.handleDisabledModel('Anthropic', model,
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

  local api_host = 'https://api.anthropic.com'
  local path = '/v1/messages'
  
  curl.post(api_host .. path, {
    headers = {
      ['Content-type'] = 'application/json',
      ['x-api-key'] = api_key,
      ['anthropic-version'] = '2023-06-01'
    },
    body = vim.fn.json_encode({
      model = model,
      max_tokens = 8192,
      system = instruction,
      messages = {{role = 'user', content = prompt}}
    }),
    callback = function(res)
      common.log("Before Anthropic callback call")
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

