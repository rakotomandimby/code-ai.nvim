# Identify code that can be factorized in a common function

I want you to review the code and tell me if there is some code in the 3 `query.lua` files that can be factorized in a common function.
If there is some code that can be factorized, provide me the refactored code with the common function.
Tell me the full new contents of the files I need to create and modify.


# OPN The duplicated logic lives in the `askHeavy` functions of the three query modules.  
They all build the same chunked payload, push it to the agent host, and schedule the provider-specific callback.  
That workflow can be extracted once and reused.

Below are the updated files (a new helper plus the refreshed providers).

---

### ✅ New shared helper

**`lua/ai/query_utils.lua`** – new file

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')

local M = {}

local function clone_table(tbl)
  local copy = {}
  if tbl then
    for k, v in pairs(tbl) do
      copy[k] = v
    end
  end
  return copy
end

function M.perform_agent_request(params)
  if not params or type(params.ask_callback) ~= 'function' then
    error('perform_agent_request requires an ask_callback function')
  end

  local callback_opts = params.callback_opts or {}

  local function schedule_callback(res)
    vim.schedule(function()
      params.ask_callback(res, clone_table(callback_opts))
    end)
  end

  if params.model == "disabled" then
    schedule_callback({
      status = 200,
      body = vim.json.encode(params.disabled_response or {}),
    })
    return
  end

  local url = (params.agent_host or '') .. '/'
  local body_chunks = {}
  table.insert(body_chunks, { type = 'api key', text = params.api_key })
  table.insert(body_chunks, { type = 'system instructions', text = params.instruction })
  table.insert(body_chunks, { type = 'model', text = params.model })

  local project_context = params.project_context or aiconfig.listScannedFilesFromConfig() or {}
  for _, context in pairs(project_context) do
    local content = aiconfig.contentOf(context)
    if content ~= nil then
      table.insert(body_chunks, { type = 'file', filename = context, content = content })
    end
  end

  table.insert(body_chunks, { type = 'prompt', text = params.prompt })

  for i = 1, #body_chunks - 1 do
    local body = vim.json.encode(body_chunks[i])
    curl.post(url, {
      headers = { ['Content-type'] = 'application/json' },
      body = body,
      callback = function() end,
    })
  end

  local final_body = vim.json.encode(body_chunks[#body_chunks])
  curl.post(url, {
    headers = { ['Content-type'] = 'application/json' },
    body = final_body,
    callback = function(res)
      schedule_callback(res)
    end,
  })
end

return M
```

---

### 🔄 Updated providers

**`lua/ai/anthropic/query.lua`**

```lua
local curl = require('plenary.curl')
local common = require('ai.common')
local query_utils = require('ai.query_utils')
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
  -- Modified: Pass upload_url, upload_token, and upload_as_public from opts to common.askCallback
  common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token, upload_as_public = opts.upload_as_public}, query.formatResult)
end

local disabled_response = {
  content = { { text = "Anthropic models are disabled" } },
  usage = { input_tokens = 0, output_tokens = 0 }
}

-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  query_utils.perform_agent_request({
    model = model,
    instruction = instruction,
    prompt = prompt,
    api_key = api_key,
    agent_host = agent_host,
    disabled_response = disabled_response,
    ask_callback = query.askCallback,
    callback_opts = {
      handleResult = opts.handleResult,
      callback = opts.callback,
      upload_url = upload_url,
      upload_token = upload_token,
      upload_as_public = upload_as_public,
    },
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
        -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
      end
    })
end

return query
```

---

**`lua/ai/googleai/query.lua`**

```lua
local curl = require('plenary.curl')
local common = require('ai.common')
local query_utils = require('ai.query_utils')
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
    -- Modified: Pass upload_url, upload_token, and upload_as_public from opts to common.askCallback
    common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = opts.upload_url, upload_token = opts.upload_token, upload_as_public = opts.upload_as_public}, query.formatResult)
end

local disabled_response = {
  candidates = { { content = { parts = { { text = "GoogleAI models are disabled" } } }, finishReason = "STOP" } },
  usageMetadata = { promptTokenCount = 0, candidatesTokenCount = 0 }
}

-- Modified: Added upload_url, upload_token, and upload_as_public parameters
function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  query_utils.perform_agent_request({
    model = model,
    instruction = instruction,
    prompt = prompt,
    api_key = api_key,
    agent_host = agent_host,
    disabled_response = disabled_response,
    ask_callback = query.askCallback,
    callback_opts = {
      handleResult = opts.handleResult,
      callback = opts.callback,
      upload_url = upload_url,
      upload_token = upload_token,
      upload_as_public = upload_as_public,
    },
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
        -- Modified: Pass upload_url, upload_token, and upload_as_public to askCallback
        vim.schedule(function() query.askCallback(res, {handleResult = opts.handleResult, callback = opts.callback, upload_url = upload_url, upload_token = upload_token, upload_as_public = upload_as_public}) end)
      end
    })
end

return query
```

---

**`lua/ai/openai/query.lua`**

```lua
local curl = require('plenary.curl')
local common = require('ai.common')
local history = require('ai.history')
local query_utils = require('ai.query_utils')

local query = {}

local promptToSave = ""
local modelUsed = ""


function query.formatResult(data, upload_url, upload_token, upload_as_public)
  common.log("Inside OpenAI formatResult")

  local function normalize_token_count(value)
    if type(value) ~= 'number' then
      value = tonumber(value) or 0
    end
    return value
  end

  local function format_tokens(count)
    count = normalize_token_count(count)
    if count >= 1000 then
      local value = count / 1000
      if value >= 100 then
        return string.format("%.0fk", value)
      elseif value >= 10 then
        return string.format("%.1fk", value)
      else
        return string.format("%.2fk", value)
      end
    end
    return tostring(count)
  end

  local prompt_tokens = normalize_token_count(type(data.usage) == 'table' and data.usage.input_tokens or 0)
  local completion_tokens = normalize_token_count(type(data.usage) == 'table' and data.usage.output_tokens or 0)
  local formatted_prompt_tokens = format_tokens(prompt_tokens)
  local formatted_completion_tokens = format_tokens(completion_tokens)

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
    .. 'OpenAI ' .. modelUsed .. ' (' .. formatted_prompt_tokens .. ' in, ' .. formatted_completion_tokens .. ' out)\n\n'

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

  query_utils.perform_agent_request({
    model = model,
    instruction = instruction,
    prompt = prompt,
    api_key = api_key,
    agent_host = agent_host,
    disabled_response = disabled_response,
    ask_callback = query.askCallback,
    callback_opts = {
      handleResult = opts.handleResult,
      callback = opts.callback,
      upload_url = upload_url,
      upload_token = upload_token,
      upload_as_public = upload_as_public,
    },
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
```

---

With this refactoring, the heavy-agent request flow lives in one shared helper and the provider modules stay focused on provider-specific concerns.

OpenAI gpt-5-codex (11255 in, 15687 out)


