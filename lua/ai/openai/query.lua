local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""


function query.formatResult(data, upload_url, upload_token, upload_as_public)
  common.log("Inside OpenAI formatResult")

  local prompt_tokens = (type(data.usage) == 'table' and tonumber(data.usage.input_tokens)) or 0
  local completion_tokens = (type(data.usage) == 'table' and tonumber(data.usage.output_tokens)) or 0

  local function collect_texts(d)
    local out = {}

    -- Prefer the convenience field if present
    if type(d.output_text) == 'string' and d.output_text ~= '' then
      table.insert(out, d.output_text)
    elseif type(d.output_text) == 'table' then
      for _, s in ipairs(d.output_text) do
        if type(s) == 'string' and s ~= '' then table.insert(out, s) end
      end
    end

    -- Fallback: traverse the output array
    if type(d.output) == 'table' then
      for _, item in ipairs(d.output) do
        if type(item) == 'table' then
          if type(item.text) == 'string' and item.text ~= '' then
            table.insert(out, item.text)
          end
          if type(item.content) == 'table' then
            for _, part in ipairs(item.content) do
              if type(part) == 'table' then
                local t = part.text or part.value
                if type(t) == 'string' and t ~= '' then
                  table.insert(out, t)
                end
              elseif type(part) == 'string' and part ~= '' then
                table.insert(out, part)
              end
            end
          elseif type(item.content) == 'string' and item.content ~= '' then
            table.insert(out, item.content)
          end
        elseif type(item) == 'string' and item ~= '' then
          table.insert(out, item)
        end
      end
    end

    return out
  end

  local pieces = collect_texts(data)
  local text = table.concat(pieces, "\n\n")

  local result = text
    .. '\n\n'
    .. 'OpenAI ' .. modelUsed .. ' (' .. tostring(prompt_tokens) .. ' in, ' .. tostring(completion_tokens) .. ' out)\n\n'

  result = common.insertWordToTitle('OPN', result)
  history.saveToHistory('openai_' .. modelUsed, promptToSave .. '\n\n' .. result)

  local model_label = (modelUsed == 'disabled') and 'disabled' or ('OpenAI (' .. modelUsed .. ')')
  common.uploadContent(upload_url, upload_token, result, model_label, upload_as_public)

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
  output = {
    { type = "message", role = "assistant", content = { { type = "output_text", text = "" } } },
    { type = "message", role = "assistant", content = { { type = "output_text", text = "OpenAI models are disabled" } } },
  },
  usage = {
    input_tokens = 0,
    output_tokens = 0,
    total_tokens = 0,
  },
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
  table.insert(body_chunks, {type = 'model', text = model})
  for _, context in pairs(project_context) do
    if aiconfig.contentOf(context) ~= nil then
      table.insert(body_chunks, {type = 'file', filename = context, content = aiconfig.contentOf(context)})
    end
  end
  table.insert(body_chunks, {type = 'prompt', text = prompt})

  -- Send all chunks without waiting for responses; 
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


function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    vim.schedule(function()
      query.askCallback(
        { status = 200, body = vim.json.encode(disabled_response) },
        { handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public }
      )
    end)
    return
  end

  local api_host = 'https://api.openai.com'
  local path = '/v1/responses'

  local input_messages = {
    {
      role = 'user',
      content = {
        { type = 'input_text', text = prompt }
      }
    }
  }

  curl.post(api_host .. path, {
    headers = {
      ['Content-type'] = 'application/json',
      ['Authorization'] = 'Bearer ' .. api_key,
    },
    body = vim.fn.json_encode({
      model = model,
      instructions = instruction, -- Responses API uses top-level instructions (no system role)
      input = input_messages,
    }),
    callback = function(res)
      common.log("Before OpenAI callback call (Responses API)")
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

