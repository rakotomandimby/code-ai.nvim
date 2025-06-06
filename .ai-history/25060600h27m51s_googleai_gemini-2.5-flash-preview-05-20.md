# Do not upload to "upload_url" if the model is "disabled"

When the model is "disabled", I would like to avoid to upload the LLM answer to the "upload_url" field.

Tell me how to do that.


# This is gemini-2.5-flash-preview-05-20 answer (16k in, 6k out)

To prevent the LLM answer from being uploaded when the model is "disabled", we will modify the `askLight` and `askHeavy` functions in each `query.lua` file (`anthropic`, `googleai`, `openai`).

The strategy is to set the `upload_url` and `upload_token` parameters to empty strings (`''`) when the model is detected as "disabled". This will leverage the existing check in `lua/ai/common.lua`'s `common.uploadContent` function, which already skips the upload if these parameters are empty.

Here are the modified files:

### `lua/ai/anthropic/query.lua`

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

-- Modified: Added upload_url and upload_token parameters
function query.formatResult(data, upload_url, upload_token)
  common.log("Inside Anthropic formatResult")
  local input_tokens = data.usage.input_tokens or 0
  local output_tokens = data.usage.output_tokens or 0

  local formatted_input_tokens = string.format("%gk", math.floor(input_tokens / 1000))
  local formatted_output_tokens = string.format("%gk", math.floor(output_tokens / 1000))

  -- Create the result string with token counts
  local result = '# This is '.. modelUsed .. ' answer (' .. formatted_input_tokens .. ' in, ' .. formatted_output_tokens .. ' out)\n\n'
  result = result .. data.content[1].text .. '\n\n'
  history.saveToHistory('claude_' .. modelUsed , promptToSave .. '\n\n' .. result)

  -- START: Upload the formatted result
  -- The common.uploadContent function already checks if url/token are empty.
  -- We ensure they are empty when the model is disabled.
  common.uploadContent(upload_url, upload_token, result, 'Anthropic (' .. modelUsed .. ')')
  -- END: Upload the formatted result

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
  local handleError = query.formatError  -- Set our custom error handler
  -- Modified: Pass upload_url and upload_token from opts to common.askCallback
  common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token}, query.formatResult)
end

local disabled_response = {
  content = { { text = "Anthropic models are disabled" } },
  usage = { input_tokens = 0, output_tokens = 0 }
}

-- Modified: Added upload_url and upload_token parameters
function query.askHeavy(model, instruction, prompt, opts, agent_host, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    -- Modified: When model is disabled, pass empty upload_url and upload_token
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = '', upload_token = ''}) end)
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
            -- Modified: Pass upload_url and upload_token to askCallback
            vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
          else
            sendNextRequest(i + 1)
          end
        end
      })
  end
  sendNextRequest(1)
end


-- Modified: Added upload_url and upload_token parameters
function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    -- Modified: When model is disabled, pass empty upload_url and upload_token
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = '', upload_token = ''}) end)
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
        -- Modified: Pass upload_url and upload_token to askCallback
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
      end
    })
end

return query

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

-- Modified: Added upload_url and upload_token parameters
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

      result = '# This is ' .. modelUsed .. ' answer (' .. formatted_prompt_tokens .. ' in, ' .. formatted_answer_tokens .. ' out)\n\n'
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

  -- START: Upload the formatted result
  -- The common.uploadContent function already checks if url/token are empty.
  -- We ensure they are empty when the model is disabled.
  common.uploadContent(upload_url, upload_token, result, 'GoogleAI (' .. modelUsed .. ')')
  -- END: Upload the formatted result

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
    local handleError = query.formatError  -- Set our custom error handler
    -- Modified: Pass upload_url and upload_token from opts to common.askCallback
    common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token}, query.formatResult)
end

local disabled_response = {
  candidates = { { content = { parts = { { text = "GoogleAI models are disabled" } } }, finishReason = "STOP" } },
  usageMetadata = { promptTokenCount = 0, candidatesTokenCount = 0 }
}

-- Modified: Added upload_url and upload_token parameters
function query.askHeavy(model, instruction, prompt, opts, agent_host, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  -- Check if model is disabled
  if model == "disabled" then
    -- Modified: When model is disabled, pass empty upload_url and upload_token
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = '', upload_token = ''}) end)
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
            -- Modified: Pass upload_url and upload_token to askCallback
            vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
          else
            sendNextRequest(i + 1)
          end
        end
      })
  end
  sendNextRequest(1)
end

-- Modified: Added upload_url and upload_token parameters
function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    -- Modified: When model is disabled, pass empty upload_url and upload_token
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = '', upload_token = ''}) end)
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
        -- Modified: Pass upload_url and upload_token to askCallback
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

-- Modified: Added upload_url and upload_token parameters
function query.formatResult(data, upload_url, upload_token)
  common.log("Inside OpenAI formatResult")
  local prompt_tokens = data.usage.prompt_tokens or 0 -- Default to 0 for disabled model
  local completion_tokens = data.usage.completion_tokens or 0 -- Default to 0 for disabled model

  local formatted_prompt_tokens = string.format("%gk", math.floor(prompt_tokens / 1000))
  local formatted_completion_tokens = string.format("%gk", math.floor(completion_tokens / 1000))

  -- Create the result string with token counts
  local result = '# This is '.. modelUsed .. ' answer (' .. formatted_prompt_tokens .. ' in, ' .. formatted_completion_tokens .. ' out)\n\n'
  result = result .. data.choices[1].message.content .. '\n\n'
  history.saveToHistory('openai_' .. modelUsed , promptToSave .. '\n\n' .. result)

  -- START: Upload the formatted result
  -- The common.uploadContent function already checks if url/token are empty.
  -- We ensure they are empty when the model is disabled.
  common.uploadContent(upload_url, upload_token, result, 'OpenAI (' .. modelUsed .. ')')
  -- END: Upload the formatted result

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
  -- Modified: Pass upload_url and upload_token from opts to common.askCallback
  common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token}, query.formatResult)
end

local disabled_response = {
  choices = { { message = { content = "OpenAI models are disabled" } } },
  usage = { prompt_tokens = 0, completion_tokens = 0 }
}

-- Modified: Added upload_url and upload_token parameters
function query.askHeavy(model, instruction, prompt, opts, agent_host, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  -- Check if model is disabled
  if model == "disabled" then
    -- Modified: When model is disabled, pass empty upload_url and upload_token
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = '', upload_token = ''}) end)
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
            -- Modified: Pass upload_url and upload_token to askCallback
            vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
          else
            sendNextRequest(i + 1)
          end
        end
      })
  end
  sendNextRequest(1)
end

-- Modified: Added upload_url and upload_token parameters
function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    -- Modified: When model is disabled, pass empty upload_url and upload_token
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, {handleResult = opts.handleResult, callback = opts.callback, upload_url = '', upload_token = ''}) end)
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
        -- Modified: Pass upload_url and upload_token to askCallback
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token}) end)
      end
    })
end

return query

```
