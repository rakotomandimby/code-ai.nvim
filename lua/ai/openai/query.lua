local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data, upload_url, upload_token, upload_as_public)
  common.log("Inside OpenAI formatResult")

  local function collect_texts(d)
    local out = {}

    if type(d.output_text) == 'string' and d.output_text ~= '' then
      table.insert(out, d.output_text)
    elseif type(d.output_text) == 'table' then
      for _, s in ipairs(d.output_text) do
        if type(s) == 'string' and s ~= '' then table.insert(out, s) end
      end
    end

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

  local prompt_tokens = type(data.usage) == 'table' and (data.usage.input_tokens or 0) or 0
  local completion_tokens = type(data.usage) == 'table' and (data.usage.output_tokens or 0) or 0
  
  local formatted_prompt_tokens = common.formatTokenCount(prompt_tokens)
  local formatted_completion_tokens = common.formatTokenCount(completion_tokens)

  local pieces = collect_texts(data)
  local text = table.concat(pieces, "\n\n")

  local result = text
    .. '\n\n'
    .. 'OpenAI ' .. modelUsed 
    .. ' (' .. formatted_prompt_tokens .. ' in, ' .. formatted_completion_tokens .. ' out)\n\n'

  result = common.insertWordToTitle('OPN', result)
  history.saveToHistory('openai_' .. modelUsed, promptToSave .. '\n\n' .. result)

  local model_label = (modelUsed == 'disabled') and 'disabled' or ('OpenAI (' .. modelUsed .. ')')
  common.uploadContent(upload_url, upload_token, result, model_label, upload_as_public)

  return result
end

function query.formatError(status, body)
  common.log("Formatting OpenAI API error: " .. body)
  local error_result
  local success, error_data = pcall(vim.fn.json_decode, body)
  
  if success and error_data and error_data.error then
    local error_type = error_data.error.type or "unknown_error"
    local error_message = error_data.error.message or "Unknown error occurred"
    local error_code = error_data.error.code or ""
    local error_param = error_data.error.param or ""
    
    error_result = string.format("# OpenAI API Error (%s)\n\n**Error Type**: %s\n", status, error_type)
    if error_code ~= "" then
      error_result = error_result .. string.format("**Error Code**: %s\n", error_code)
    end
    if error_param ~= "" then
      error_result = error_result .. string.format("**Parameter**: %s\n", error_param)
    end
    error_result = error_result .. string.format("**Message**: %s\n", error_message)
  else
    error_result = string.format("# OpenAI API Error (%s)\n\n```\n%s\n```", status, body)
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

function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    common.handleDisabledModel('OpenAI', model,
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
    common.handleDisabledModel('OpenAI', model,
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
      instructions = instruction,
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

