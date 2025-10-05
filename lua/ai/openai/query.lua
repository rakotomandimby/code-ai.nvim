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
  local handleError = query.formatError  -- Set our custom error handler
  -- Modified: Pass upload_url, upload_token, and upload_as_public from opts to common.askCallback
  common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token, upload_as_public = opts.upload_as_public}, query.formatResult)
end

local disabled_response = {
  choices = { { message = { content = "OpenAI models are disabled" } } },
  usage = { prompt_tokens = 0, completion_tokens = 0 }
}

-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  -- Check if model is disabled
  if model == "disabled" then
    -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
    return
  end

  local url = agent_host .. '/'
  local project_context = aiconfig.listScannedFilesFromConfig()
  local body_chunks = {}
  table.insert(body_chunks, {type = 'api key', text = api_key})
  table.insert(body_chunks, {type = 'system instructions', text = instruction})
  table.insert(body_chunks, {role = 'model', text = model})
  for _, context in pairs(project_context) do
    if aiconfig.contentOf(context) ~= nil then
      table.insert(body_chunks, {type = 'file', filename = context, content = aiconfig.contentOf(context)})
    end
  end
  table.insert(body_chunks, {type = 'prompt', text = prompt})

  -- Send all chunks without waiting for responses; 
  local size = #body_chunks
  for i = 1, #body_chunks - 1 do
    local message = body_chunks[i]
    local body = vim.json.encode(message)
    curl.post(url, {
      headers = {['Content-type'] = 'application/json'},
      body = body,
      callback = function(res) end
    })
  end

  -- wait for the response only for the last one.
  local i = #body_chunks
  local message = body_chunks[i]
  local body = vim.json.encode(message)

  curl.post(url, {
    headers = {['Content-type'] = 'application/json'},
    body = body,
    callback = function(res)
      -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
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
      body = vim.fn.json_encode(
        {
          model = model,
          messages = (function()
            local messages = {}
            if string.sub(model, 1, 2) == 'o1' or string.sub(model, 1, 2) == 'o3' or string.sub(model, 1, 2) == 'o4' then
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

