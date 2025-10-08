# Identify code that can be factorized in a common function

I want you to review the code and tell me if there is some code in the 3 `query.lua` files that can be factorized in a common function.
If there is some code that can be factorized, provide me the refactored code with the common function.
Tell me the full new contents of the files I need to create and modify.


# GGL You're right, there's a significant amount of repetitive code in the `askHeavy`, `askLight`, and `askCallback` functions across the three `query.lua` files. We can factorize this into a new common module to improve maintainability and reduce redundancy.

The main areas for factorization are:
1.  **Setting the current query context:** Storing the `prompt` and `model` for history and logging.
2.  **Handling disabled models:** The logic for returning a predefined "disabled" response.
3.  **`askHeavy` logic:** The process of sending chunks of context and the final prompt to an agent host.
4.  **`askCallback` structure:** The common pattern of calling `common.askCallback` with provider-specific `formatError` and `formatResult` functions.
5.  **`formatResult` and `formatError` parameters:** Adjusting these to receive the query context directly instead of relying on module-level globals.

Here's the refactored code:

---

### New File: `lua/ai/query_common.lua`

This file will contain the common functions.

```lua
-- lua/ai/query_common.lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query_common = {}

--- Handles the scenario where an AI model is disabled.
-- It schedules a call to the provider's ask_callback with a predefined disabled response.
-- @param opts table The options table for the query, including handleResult, callback, and upload details.
-- @param ask_callback function The provider-specific ask_callback function.
-- @param disabled_response_data table The JSON-decodable data for a disabled response.
function query_common.handle_disabled_model(opts, ask_callback, disabled_response_data)
  common.log("Model is disabled. Returning pre-defined disabled response.")
  vim.schedule(function()
    -- Pass a dummy prompt_to_save and model_used for disabled responses if formatResult needs them
    opts.current_prompt_to_save = ""
    opts.current_model_used = "disabled"
    ask_callback({ status = 200, body = vim.json.encode(disabled_response_data) }, opts)
  end)
end

--- Sends a 'heavy' query to an AI agent host, including project context.
-- This function encapsulates the logic for chunking and sending data to an agent.
-- @param model string The name of the AI model to use.
-- @param instruction string System instructions for the AI.
-- @param prompt string The user's prompt.
-- @param opts table The options table for the query (includes handleResult, callback, upload details).
-- @param api_key string The API key for the AI service.
-- @param agent_host string The URL of the AI agent host.
-- @param ask_callback function The provider-specific ask_callback function to handle the final response.
function query_common.send_heavy_query(model, instruction, prompt, opts, api_key, agent_host, ask_callback)
  -- Store prompt and model in opts for later retrieval in formatResult
  opts.current_prompt_to_save = prompt
  opts.current_model_used = model

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

  -- Send all chunks except the last one without waiting for responses
  for i = 1, #body_chunks - 1 do
    local message = body_chunks[i]
    local body = vim.json.encode(message)
    curl.post(url, {
      headers = {['Content-type'] = 'application/json'},
      body = body,
      callback = function(res)
        -- Log any errors even for non-final chunks, but don't pass to main callback
        if res.status ~= 200 then
          common.log("Agent intermediate chunk upload failed. Status: " .. res.status .. ", Body: " .. res.body)
        end
      end
    })
  end

  -- Send the last chunk and wait for its response
  local i = #body_chunks
  local message = body_chunks[i]
  local body = vim.json.encode(message)

  curl.post(url, {
    headers = {['Content-type'] = 'application/json'},
    body = body,
    callback = function(res)
      vim.schedule(function()
        ask_callback(res, opts)
      end)
    end
  })
end

--- Creates a base askCallback function for a specific AI provider.
-- This centralizes the common logic for handling API responses and errors.
-- @param format_error_func function The provider-specific function to format API errors.
-- @param format_result_func function The provider-specific function to format successful API results.
-- @return function A standardized askCallback function.
function query_common.create_base_ask_callback(format_error_func, format_result_func)
  return function(res, opts)
    local handleError = format_error_func
    -- Extract upload options from opts, as they are now consistently passed within opts
    local upload_opts = {
      upload_url = opts.upload_url,
      upload_token = opts.upload_token,
      upload_as_public = opts.upload_as_public,
    }
    common.askCallback(res, {handleResult = opts.handleResult, handleError = handleError, callback = opts.callback, upload_url = upload_opts.upload_url, upload_token = upload_opts.upload_token, upload_as_public = upload_opts.upload_as_public}, function(data, upload_url, upload_token, upload_as_public)
      -- Pass prompt_to_save and model_used from opts to format_result_func
      return format_result_func(data, upload_url, upload_token, upload_as_public, opts.current_prompt_to_save, opts.current_model_used)
    end)
  end
end

return query_common

```

---

### Modified: `lua/ai/anthropic/query.lua`

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local history = require('ai.history')
local query_common = require('ai.query_common') -- New import
local query = {}

local disabled_response = {
  content = { { text = "Anthropic models are disabled" } },
  usage = { input_tokens = 0, output_tokens = 0 }
}

--- Formats the successful Anthropic API response.
-- @param data table The decoded JSON response from the Anthropic API.
-- @param upload_url string The URL for uploading content.
-- @param upload_token string The token for uploading content.
-- @param upload_as_public boolean Whether the upload should be public.
-- @param promptToSave string The original prompt used for the query.
-- @param modelUsed string The model used for the query.
-- @return string The formatted result string.
function query.formatResult(data, upload_url, upload_token, upload_as_public, promptToSave, modelUsed)
  common.log("Inside Anthropic formatResult")
  local input_tokens = data.usage.input_tokens or 0
  local output_tokens = data.usage.output_tokens or 0

  local formatted_input_tokens = string.format("%gk", math.floor(input_tokens / 1000))
  local formatted_output_tokens = string.format("%gk", math.floor(output_tokens / 1000))

  -- Create the result string with token counts
  local result = data.content[1].text .. '\n\n' .. 'Anthropic '.. modelUsed .. ' (' .. formatted_input_tokens .. ' in, ' .. formatted_output_tokens .. ' out)\n\n'
  result = common.insertWordToTitle('ANT', result)
  history.saveToHistory('claude_' .. modelUsed , promptToSave .. '\n\n' .. result)

  common.uploadContent(upload_url, upload_token, result, 'Anthropic (' .. modelUsed .. ')', upload_as_public)

  return result
end

--- Formats an Anthropic API error response.
-- @param status number The HTTP status code of the response.
-- @param body string The raw response body.
-- @return string The formatted error message.
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

-- Re-create askCallback using the common factory
query.askCallback = query_common.create_base_ask_callback(query.formatError, query.formatResult)

--- Initiates a 'heavy' Anthropic query using an agent host.
-- @param model string The name of the Anthropic model to use.
-- @param instruction string System instructions for the AI.
-- @param prompt string The user's prompt.
-- @param opts table The options table for the query (includes handleResult, callback, upload details).
-- @param api_key string The Anthropic API key.
-- @param agent_host string The URL of the AI agent host.
function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host)
  if model == "disabled" then
    query_common.handle_disabled_model(opts, query.askCallback, disabled_response)
    return
  end
  query_common.send_heavy_query(model, instruction, prompt, opts, api_key, agent_host, query.askCallback)
end

--- Initiates a 'light' Anthropic query directly to the Anthropic API.
-- @param model string The name of the Anthropic model to use.
-- @param instruction string System instructions for the AI.
-- @param prompt string The user's prompt.
-- @param opts table The options table for the query (includes handleResult, callback, upload details).
-- @param api_key string The Anthropic API key.
function query.askLight(model, instruction, prompt, opts, api_key)
  opts.current_prompt_to_save = prompt
  opts.current_model_used = model

  if model == "disabled" then
    query_common.handle_disabled_model(opts, query.askCallback, disabled_response)
    return
  end

  local api_host = 'https://api.anthropic.com'
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

---

### Modified: `lua/ai/googleai/query.lua`

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local history = require('ai.history')
local query_common = require('ai.query_common') -- New import
local query = {}

local disabled_response = {
  candidates = { { content = { parts = { { text = "GoogleAI models are disabled" } } }, finishReason = "STOP" } },
  usageMetadata = { promptTokenCount = 0, candidatesTokenCount = 0 }
}

--- Formats the successful GoogleAI API response.
-- @param data table The decoded JSON response from the GoogleAI API.
-- @param upload_url string The URL for uploading content.
-- @param upload_token string The token for uploading content.
-- @param upload_as_public boolean Whether the upload should be public.
-- @param promptToSave string The original prompt used for the query.
-- @param modelUsed string The model used for the query.
-- @return string The formatted result string.
function query.formatResult(data, upload_url, upload_token, upload_as_public, promptToSave, modelUsed)
  common.log("Inside GoogleAI formatResult")
  local result = ''
  local candidates_number = #data['candidates']
  if candidates_number == 1 then
    if data['candidates'][1]['content'] == nil then
      result = '\n#GoogleAI error\n\nGoogleAI stopped with the reason: ' .. data['candidates'][1]['finishReason'] .. '\n'
      return result
    else
      local prompt_tokens = data['usageMetadata']['promptTokenCount'] or 0
      local answer_tokens = data['usageMetadata']['candidatesTokenCount'] or 0

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

  common.uploadContent(upload_url, upload_token, result, 'GoogleAI (' .. modelUsed .. ')', upload_as_public)

  return result
end

--- Formats a GoogleAI API error response.
-- @param status number The HTTP status code of the response.
-- @param body string The raw response body.
-- @return string The formatted error message.
function query.formatError(status, body)
  common.log("Formatting GoogleAI API error: " .. body)
  local error_result
  local success, error_data = pcall(vim.fn.json_decode, body)
  if success and error_data and error_data.error then
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
    error_result = string.format("# GoogleAI API Error (%s)\n\n```\n%s\n```", status, body)
  end
  return error_result
end

-- Re-create askCallback using the common factory
query.askCallback = query_common.create_base_ask_callback(query.formatError, query.formatResult)

--- Initiates a 'heavy' GoogleAI query using an agent host.
-- @param model string The name of the GoogleAI model to use.
-- @param instruction string System instructions for the AI.
-- @param prompt string The user's prompt.
-- @param opts table The options table for the query (includes handleResult, callback, upload details).
-- @param api_key string The GoogleAI API key.
-- @param agent_host string The URL of the AI agent host.
function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host)
  if model == "disabled" then
    query_common.handle_disabled_model(opts, query.askCallback, disabled_response)
    return
  end
  query_common.send_heavy_query(model, instruction, prompt, opts, api_key, agent_host, query.askCallback)
end

--- Initiates a 'light' GoogleAI query directly to the GoogleAI API.
-- @param model string The name of the GoogleAI model to use.
-- @param instruction string System instructions for the AI.
-- @param prompt string The user's prompt.
-- @param opts table The options table for the query (includes handleResult, callback, upload details).
-- @param api_key string The GoogleAI API key.
function query.askLight(model, instruction, prompt, opts, api_key)
  opts.current_prompt_to_save = prompt
  opts.current_model_used = model

  if model == "disabled" then
    query_common.handle_disabled_model(opts, query.askCallback, disabled_response)
    return
  end

  local api_host = 'https://generativelanguage.googleapis.com'
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
        vim.schedule(function() query.askCallback(res, opts) end)
      end
    })
end

return query
```

---

### Modified: `lua/ai/openai/query.lua`

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local history = require('ai.history')
local query_common = require('ai.query_common') -- New import
local query = {}

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

--- Formats the successful OpenAI API response.
-- @param data table The decoded JSON response from the OpenAI API.
-- @param upload_url string The URL for uploading content.
-- @param upload_token string The token for uploading content.
-- @param upload_as_public boolean Whether the upload should be public.
-- @param promptToSave string The original prompt used for the query.
-- @param modelUsed string The model used for the query.
-- @return string The formatted result string.
function query.formatResult(data, upload_url, upload_token, upload_as_public, promptToSave, modelUsed)
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

--- Formats an OpenAI API error response.
-- @param status number The HTTP status code of the response.
-- @param body string The raw response body.
-- @return string The formatted error message.
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

-- Re-create askCallback using the common factory
query.askCallback = query_common.create_base_ask_callback(query.formatError, query.formatResult)

--- Initiates a 'heavy' OpenAI query using an agent host.
-- @param model string The name of the OpenAI model to use.
-- @param instruction string System instructions for the AI.
-- @param prompt string The user's prompt.
-- @param opts table The options table for the query (includes handleResult, callback, upload details).
-- @param api_key string The OpenAI API key.
-- @param agent_host string The URL of the AI agent host.
function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host)
  if model == "disabled" then
    query_common.handle_disabled_model(opts, query.askCallback, disabled_response)
    return
  end
  query_common.send_heavy_query(model, instruction, prompt, opts, api_key, agent_host, query.askCallback)
end

--- Initiates a 'light' OpenAI query directly to the OpenAI API.
-- @param model string The name of the OpenAI model to use.
-- @param instruction string System instructions for the AI.
-- @param prompt string The user's prompt.
-- @param opts table The options table for the query (includes handleResult, callback, upload details).
-- @param api_key string The OpenAI API key.
function query.askLight(model, instruction, prompt, opts, api_key)
  opts.current_prompt_to_save = prompt
  opts.current_model_used = model

  if model == "disabled" then
    query_common.handle_disabled_model(opts, query.askCallback, disabled_response)
    return
  end

  local api_host = 'https://api.openai.com'
  local path = '/v1/responses' -- Assuming this custom /v1/responses endpoint is intentional.
                               -- For standard OpenAI Chat Completions, it would typically be '/v1/chat/completions'.
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
      vim.schedule(function() query.askCallback(res, opts) end)
    end
  })
end

return query
```

---

### Modified: `lua/ai/init.lua`

This file needs to be updated to match the new, cleaner function signatures for `askHeavy` and `askLight` (removing the redundant `upload_url`, `upload_token`, `upload_as_public` parameters, as they are now part of the `opts` table).

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
  upload_as_public = false,
  append_embeded_system_instructions = true,
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
}

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
  vim.bo[bufnr].filetype = 'markdown'
  vim.api.nvim_win_set_option(win_id, 'wrap', true)


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

  if (number_of_files == 0 or not use_anthropic_agent or not use_googleai_agent or not use_openai_agent ) then
    update = M.createPopup(M.fill(def.loading_tpl , args), width - 8, height - 4)
  else
    local scanned_files = aiconfig.listScannedFilesAsFormattedTable()
    update = M.createPopup(M.fill(def.loading_tpl .. scanned_files, args), width - 8, height - 4)
  end
  local prompt = M.fill(def.prompt_tpl, args)
  
  local append_embeded = M.opts.append_embeded_system_instructions
  if def.append_embeded_system_instructions ~= nil then
    append_embeded = def.append_embeded_system_instructions
  end
  local instruction = aiconfig.getSystemInstructions(append_embeded)

  local anthropic_model = def.anthropic_model or M.opts.anthropic_model
  local googleai_model = def.googleai_model or M.opts.googleai_model
  local openai_model = def.openai_model or M.opts.openai_model

  -- If command-level models are set, use them
  if def.anthropic_model and def.anthropic_model ~= '' then
    anthropic_model = def.anthropic_model
  end
  if def.googleai_model and def.googleai_model ~= '' then
    googleai_model = def.googleai_model
  end
  if def.openai_model and def.openai_model ~= '' then
    openai_model = def.openai_model
  end

  -- START: Prepare common options for all LLM queries, including upload details
  -- The upload details are now passed as part of the opts table
  local common_query_opts = {
    upload_url = M.opts.upload_url,
    upload_token = M.opts.upload_token,
    upload_as_public = M.opts.upload_as_public,
  }
  -- END: Prepare common options for all LLM queries

  local function handleResult(output, output_key)
    args[output_key] = output
    args.output = (args.anthropic_output or '').. (args.googleai_output or '') .. (args.openai_output or '')
    update(M.fill(def.result_tpl or '${output}', args))
  end

  -- These opts tables now contain the upload details directly
  local askHandleResultAndCallbackAnthropic = {
    handleResult = function(output) return handleResult(output, 'anthropic_output') end,
    callback = function() end,
    upload_url = common_query_opts.upload_url,
    upload_token = common_query_opts.upload_token,
    upload_as_public = common_query_opts.upload_as_public,
  }

  local askHandleResultAndCallbackGoogleAI = {
    handleResult = function(output) return handleResult(output, 'googleai_output') end,
    callback = function() end,
    upload_url = common_query_opts.upload_url,
    upload_token = common_query_opts.upload_token,
    upload_as_public = common_query_opts.upload_as_public,
  }

  local askHandleResultAndCallbackOpenAI = {
    handleResult = function(output) return handleResult(output, 'openai_output') end,
    callback = function() end,
    upload_url = common_query_opts.upload_url,
    upload_token = common_query_opts.upload_token,
    upload_as_public = common_query_opts.upload_as_public,
  }

  if (number_of_files == 0
        or not use_anthropic_agent
        or not use_googleai_agent
        or not use_openai_agent) then
    common.log("Not using agents")
    anthropic.askLight(
      anthropic_model,
      instruction,
      prompt,
      askHandleResultAndCallbackAnthropic, -- opts parameter
      M.opts.anthropic_api_key
    )
    googleai.askLight(
      googleai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackGoogleAI, -- opts parameter
      M.opts.googleai_api_key
    )
    openai.askLight(
      openai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackOpenAI, -- opts parameter
      M.opts.openai_api_key
    )
  else
    common.log("Using agents")
    anthropic.askHeavy(
      anthropic_model,
      instruction,
      prompt,
      askHandleResultAndCallbackAnthropic, -- opts parameter
      M.opts.anthropic_api_key,
      M.opts.anthropic_agent_host
    )
    googleai.askHeavy(
      googleai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackGoogleAI, -- opts parameter
      M.opts.googleai_api_key,
      M.opts.googleai_agent_host
    )
    openai.askHeavy(
      openai_model,
      instruction,
      prompt,
      askHandleResultAndCallbackOpenAI, -- opts parameter
      M.opts.openai_api_key,
      M.opts.openai_agent_host
    )
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

  if M.opts.anthropic_model == '' or  M.opts.googleai_model == '' or M.opts.openai_model == '' then
    error('You need to set both anthropic_model and googleai_model and openai_model')
  end
  if M.opts.anthropic_api_key ==''or M.opts.googleai_api_key == '' or M.opts.openai_api_key == '' then
    error('You need to set both anthropic_api_key and googleai_api_key and openai_api_key')
  end

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

---

### Summary of Changes:

**New File:**
*   `lua/ai/query_common.lua`: Contains `handle_disabled_model`, `send_heavy_query`, and `create_base_ask_callback`. This centralizes the common logic.

**Modified Files:**
*   `lua/ai/anthropic/query.lua`, `lua/ai/googleai/query.lua`, `lua/ai/openai/query.lua`:
    *   Removed `promptToSave` and `modelUsed` global variables. The query context (`prompt` and `model`) is now stored in the `opts` table as `opts.current_prompt_to_save` and `opts.current_model_used` and passed explicitly to `formatResult`.
    *   `query.askCallback` is now created using `query_common.create_base_ask_callback`, which takes the provider-specific `formatError` and `formatResult` functions.
    *   `query.askHeavy` now calls `query_common.send_heavy_query`, reducing its local implementation to just the `disabled` model check. The `upload_url`, `upload_token`, `upload_as_public` parameters were removed from its signature as they are now expected within the `opts` table.
    *   `query.askLight` also includes the `opts.current_prompt_to_save` and `opts.current_model_used` assignments and the `disabled` model check. The `upload_url`, `upload_token`, `upload_as_public` parameters were removed from its signature.
    *   `query.formatResult` functions now accept `promptToSave` and `modelUsed` as explicit parameters.
*   `lua/ai/init.lua`:
    *   The calls to `anthropic.askLight/askHeavy`, `googleai.askLight/askHeavy`, and `openai.askLight/askHeavy` have been updated to reflect the simplified function signatures, removing the redundant `upload_url`, `upload_token`, `upload_as_public` arguments at the end of the call, as these are already included in the `askHandleResultAndCallbackX` `opts` table.

These changes significantly reduce code duplication and make the overall structure more modular and easier to manage.

GoogleAI gemini-2.5-flash (13k in, 10k out)


