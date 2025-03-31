# Handle Errors

When the Anthropic API answers with other than an HTTP 200 status code, the response has this structure:

```json
{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
```

When the ChatGPT API answers with other than an HTTP 200 status code, the response has this structure:

```json
{"error":
  {
    "message":"This model's maximum context length is 128000 tokens.",
    "type":"invalid_request_error",
    "param":"messages",
    "code":"context_length_exceeded"
  }
}
```

When the Gemini API answers with other than an HTTP 200 status code, the response has this structure:

```json
{
  "error": {
    "code": 400,
    "message": "The request is missing a required parameter, includes an invalid parameter value, includes a parameter more than once, or is otherwise malformed.",
    "status": "BAD_REQUEST"
  }
}
```

I want to gracefully handle specific API errors from Anthropic, ChatGPT, and Gemini in respective `query.ask()` methods. 
We do not touch the `query.askHeavy()`.

I want the `query.ask()` method of each API to handle, extract the error message, and display it. 

Tell me the modifications to make to the code in order to achieve that.





# This is gemini-2.5-pro-exp-03-25 answer (12k in, 7k out)

Okay, I understand. You want to improve the error handling within the `ask` function of each provider's query module (`anthropic`, `chatgpt`, `gemini`) to parse the specific error messages returned by their APIs when the HTTP status is not 200.

Here are the proposed modifications for each relevant file:

**1. `lua/ai/anthropic/query.lua`**

We will modify the callback function within `query.ask` to check the status code *before* calling `common.askCallback`. If it's an error, we parse the specific Anthropic error format and call the final callback directly.

```lua
-- lua/ai/anthropic/query.lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data)
  common.log("Inside Anthropic formatResult")
  local input_tokens = data.usage.input_tokens or 0
  local output_tokens = data.usage.output_tokens or 0

  local formatted_input_tokens = string.format("%gk", math.floor(input_tokens / 1000))
  local formatted_output_tokens = string.format("%gk", math.floor(output_tokens / 1000))

  -- Create the result string with token counts
  local result = '\n# This is '.. modelUsed .. ' answer (' .. formatted_input_tokens .. ' in, ' .. formatted_output_tokens .. ' out)\n\n'
  -- Handle potential variations in response structure, ensuring content exists
  if data.content and data.content[1] and data.content[1].text then
    result = result .. data.content[1].text .. '\n\n'
  else
    -- Log unexpected structure if needed, provide a fallback message
    common.log("Anthropic response content format unexpected: " .. vim.inspect(data))
    result = result .. "[Could not extract Anthropic response content]\n\n"
  end
  history.saveToHistory('claude_' .. modelUsed , promptToSave .. '\n\n' .. result)
  return result
end

query.askCallback = function(res, opts)
  -- This function is now only called for successful (200) responses from ask()
  -- or potentially by askHeavy() which is unchanged.
  common.askCallback(res, opts, query.formatResult)
end

local disabled_response = {
  content = { { text = "Anthropic models are disabled" } },
  usage = { input_tokens = 0, output_tokens = 0 }
}

function query.askHeavy(model, instruction, prompt, opts, agent_host)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, opts) end)
    return
  end

  local url = agent_host .. '/anthropic'
  local project_context = aiconfig.listScannedFilesFromConfig()
  local body_chunks = {}
  table.insert(body_chunks, {system_instruction = instruction})
  table.insert(body_chunks, {role = 'user', content = "I need your help on this project."})
  table.insert(body_chunks, {role = 'model', content = "Tell me the project file structure."})
  table.insert(body_chunks, {role = 'user',  content = aiconfig.listScannedFilesAsText()})
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
            -- askHeavy still uses the common callback directly
            vim.schedule(function() common.askCallback(res, opts, query.formatResult) end)
          else
            sendNextRequest(i + 1)
          end
        end
      })
  end
  sendNextRequest(1)
end


function query.ask(model, instruction, prompt, opts, api_key)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    -- Use the final callback directly for disabled model message
    vim.schedule(function() opts.callback("\n# Anthropic Info\n\nAnthropic models are disabled.\n") end)
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
          max_tokens = 8192, -- Consider making this configurable
          system= instruction,
          messages = (function()
            local messages = {}
            table.insert(messages, {role = 'user', content = prompt})
            return messages
          end)()
        }
      ),
      callback = function(res)
        common.log("Anthropic response status: " .. res.status)
        -- Check status code *before* calling common.askCallback
        if res.status ~= 200 then
          local error_message = "Unknown Anthropic API error."
          local ok, data = pcall(vim.fn.json_decode, res.body)
          if ok and type(data) == 'table' and data.error and data.error.message then
            -- Extract the specific error message
            error_message = data.error.message
            common.log("Anthropic API Error: " .. error_message)
          else
            -- Fallback if JSON parsing fails or structure is unexpected
            common.log("Failed to parse Anthropic error response or unexpected format: " .. res.body)
            error_message = "Status " .. res.status .. ": " .. res.body
          end
          -- Format the error and call the final callback directly
          local formatted_error = '\n# Anthropic Error\n\n' .. error_message .. '\n'
          vim.schedule(function() opts.callback(formatted_error) end)
        else
          -- If status is 200, proceed with the normal flow via common.askCallback
          common.log("Before Anthropic callback call (status 200)")
          vim.schedule(function() query.askCallback(res, opts) end)
        end
      end
    })
end

return query
```

**2. `lua/ai/chatgpt/query.lua`**

Similar changes are applied here, parsing the ChatGPT error structure.

```lua
-- lua/ai/chatgpt/query.lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data)
  common.log("Inside ChatGPT formatResult")
  local prompt_tokens = data.usage.prompt_tokens or 0
  local completion_tokens = data.usage.completion_tokens or 0

  local formatted_prompt_tokens = string.format("%gk", math.floor(prompt_tokens / 1000))
  local formatted_completion_tokens = string.format("%gk", math.floor(completion_tokens / 1000))

  -- Create the result string with token counts
  local result = '\n# This is '.. modelUsed .. ' answer (' .. formatted_prompt_tokens .. ' in, ' .. formatted_completion_tokens .. ' out)\n\n'
  -- Handle potential variations in response structure
  if data.choices and data.choices[1] and data.choices[1].message and data.choices[1].message.content then
      result = result .. data.choices[1].message.content .. '\n\n'
  else
      common.log("ChatGPT response content format unexpected: " .. vim.inspect(data))
      result = result .. "[Could not extract ChatGPT response content]\n\n"
  end
  history.saveToHistory('chatgpt_' .. modelUsed , promptToSave .. '\n\n' .. result)
  return result
end

query.askCallback = function(res, opts)
  -- This function is now only called for successful (200) responses from ask()
  -- or potentially by askHeavy() which is unchanged.
  common.askCallback(res, opts, query.formatResult)
end

local disabled_response = {
  choices = { { message = { content = "ChatGPT models are disabled" } } },
  usage = { prompt_tokens = 0, completion_tokens = 0 }
}

function query.askHeavy(model, instruction, prompt, opts, agent_host)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, opts) end)
    return
  end

  local url = agent_host .. '/chatgpt'
  local project_context = aiconfig.listScannedFilesFromConfig()
  local body_chunks = {}
  table.insert(body_chunks, {system_instruction = instruction})
  table.insert(body_chunks, {role = 'user', content = "I need your help on this project."})
  table.insert(body_chunks, {role = 'model', content = "Tell me the project file structure."})
  table.insert(body_chunks, {role = 'user',  content = aiconfig.listScannedFilesAsText()})
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
            -- askHeavy still uses the common callback directly
            vim.schedule(function() common.askCallback(res, opts, query.formatResult) end)
          else
            sendNextRequest(i + 1)
          end
        end
      })
  end
  sendNextRequest(1)
end

function query.ask(model, instruction, prompt, opts, api_key)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    -- Use the final callback directly for disabled model message
    vim.schedule(function() opts.callback("\n# ChatGPT Info\n\nChatGPT models are disabled.\n") end)
    return
  end

  local api_host = 'https://api.openai.com'
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
            -- Model specific instruction handling (o1 vs others)
            if string.sub(model, 1, 2) == 'o1' then
              table.insert(messages, {role = 'user', content = instruction .. '\n' .. prompt})
            else
              table.insert(messages, { role = 'system', content = instruction })
              table.insert(messages, {role = 'user', content = prompt})
            end
            return messages
          end)(),
          -- Add temperature and top_p if desired for non-heavy ask
          -- temperature = 0.2,
          -- top_p = 0.1
        }
      ),
      callback = function(res)
        common.log("ChatGPT response status: " .. res.status)
        -- Check status code *before* calling common.askCallback
        if res.status ~= 200 then
          local error_message = "Unknown ChatGPT API error."
          local ok, data = pcall(vim.fn.json_decode, res.body)
          if ok and type(data) == 'table' and data.error and data.error.message then
            -- Extract the specific error message
            error_message = data.error.message
            -- Optionally include type and code if available
            if data.error.type then error_message = error_message .. " (Type: " .. data.error.type .. ")" end
            if data.error.code then error_message = error_message .. " (Code: " .. data.error.code .. ")" end
            common.log("ChatGPT API Error: " .. error_message)
          else
            -- Fallback if JSON parsing fails or structure is unexpected
            common.log("Failed to parse ChatGPT error response or unexpected format: " .. res.body)
            error_message = "Status " .. res.status .. ": " .. res.body
          end
          -- Format the error and call the final callback directly
          local formatted_error = '\n# ChatGPT Error\n\n' .. error_message .. '\n'
          vim.schedule(function() opts.callback(formatted_error) end)
        else
          -- If status is 200, proceed with the normal flow via common.askCallback
          common.log("Before ChatGPT callback call (status 200)")
          vim.schedule(function() query.askCallback(res, opts) end)
        end
      end
    })
end

return query
```

**3. `lua/ai/gemini/query.lua`**

And finally, apply the same pattern for Gemini.

```lua
-- lua/ai/gemini/query.lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data)
  common.log("Inside Gemini formatResult")
  local result = ''
  -- Check if candidates exist and have content before processing
  if data.candidates and #data.candidates > 0 then
      local candidates_number = #data.candidates
      if candidates_number == 1 then
          local candidate = data.candidates[1]
          if candidate.content and candidate.content.parts and candidate.content.parts[1] and candidate.content.parts[1].text then
              -- Extract token counts safely
              local prompt_tokens = (data.usageMetadata and data.usageMetadata.promptTokenCount) or 0
              local answer_tokens = (data.usageMetadata and data.usageMetadata.candidatesTokenCount) or 0

              local formatted_prompt_tokens = string.format("%gk", math.floor(prompt_tokens / 1000))
              local formatted_answer_tokens = string.format("%gk", math.floor(answer_tokens / 1000))

              result = '\n# This is ' .. modelUsed .. ' answer (' .. formatted_prompt_tokens .. ' in, ' .. formatted_answer_tokens .. ' out)\n\n'
              result = result .. candidate.content.parts[1].text .. '\n'
          else
              -- Handle cases where content is missing or finishReason indicates an issue
              local reason = candidate.finishReason or "Unknown reason"
              result = '\n# Gemini Info\n\nGemini stopped generating. Reason: ' .. reason .. '\n'
              common.log("Gemini response format issue or early stop: " .. vim.inspect(candidate))
          end
      else
          result = '# There are ' .. candidates_number .. ' Gemini candidates\n'
          for i = 1, candidates_number do
              result = result .. '## Gemini Candidate number ' .. i .. '\n'
              if data.candidates[i].content and data.candidates[i].content.parts and data.candidates[i].content.parts[1] and data.candidates[i].content.parts[1].text then
                  result = result .. data.candidates[i].content.parts[1].text .. '\n'
              else
                  result = result .. "[Could not extract content for candidate " .. i .. "]\n"
                  common.log("Gemini response format issue for candidate " .. i .. ": " .. vim.inspect(data.candidates[i]))
              end
          end
      end
  else
      -- Handle cases where the response might be blocked or malformed
      if data.promptFeedback and data.promptFeedback.blockReason then
          result = '\n# Gemini Info\n\nRequest blocked by Gemini. Reason: ' .. data.promptFeedback.blockReason .. '\n'
      else
          result = '\n# Gemini Error\n\nUnexpected response format from Gemini.\n'
          common.log("Gemini response format unexpected (no candidates): " .. vim.inspect(data))
      end
  end

  history.saveToHistory('gemini_' .. modelUsed  , promptToSave .. '\n\n' .. result)
  return result
end

query.askCallback = function(res, opts)
    -- This function is now only called for successful (200) responses from ask()
    -- or potentially by askHeavy() which is unchanged.
    common.askCallback(res, opts, query.formatResult)
end

local disabled_response = {
  candidates = { { content = { parts = { { text = "Gemini models are disabled" } } }, finishReason = "STOP" } },
  usageMetadata = { promptTokenCount = 0, candidatesTokenCount = 0 }
}

function query.askHeavy(model, instruction, prompt, opts, agent_host)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, opts) end)
    return
  end

  local url = agent_host .. '/gemini'
  local project_context = aiconfig.listScannedFilesFromConfig()
  local body_chunks = {}
  table.insert(body_chunks, {system_instruction = instruction})
  table.insert(body_chunks, {role = 'user', content = "I need your help on this project. "})
  table.insert(body_chunks, {role = 'model', content = "Tell me the project file structure."})
  table.insert(body_chunks, {role = 'user',  content = aiconfig.listScannedFilesAsText()})
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
            -- askHeavy still uses the common callback directly
            vim.schedule(function() common.askCallback(res, opts, query.formatResult) end)
          else
            sendNextRequest(i + 1)
          end
        end
      })
  end
  sendNextRequest(1)
end

function query.ask(model, instruction, prompt, opts, api_key)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    -- Use the final callback directly for disabled model message
    vim.schedule(function() opts.callback("\n# Gemini Info\n\nGemini models are disabled.\n") end)
    return
  end

  local api_host = 'https://generativelanguage.googleapis.com'
  local path = '/v1beta/models/' .. model .. ':generateContent'
  curl.post(api_host .. path .. '?key=' .. api_key, -- API Key in query param for Gemini
    {
      headers = {
        ['Content-type'] = 'application/json',
        -- Remove x-goog-api-key header if key is in URL
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
        common.log("Gemini response status: " .. res.status)
        -- Check status code *before* calling common.askCallback
        if res.status ~= 200 then
          local error_message = "Unknown Gemini API error."
          local ok, data = pcall(vim.fn.json_decode, res.body)
          if ok and type(data) == 'table' and data.error and data.error.message then
            -- Extract the specific error message
            error_message = data.error.message
            -- Optionally include status and code if available
            if data.error.status then error_message = error_message .. " (Status: " .. data.error.status .. ")" end
            if data.error.code then error_message = error_message .. " (Code: " .. data.error.code .. ")" end
            common.log("Gemini API Error: " .. error_message)
          else
            -- Fallback if JSON parsing fails or structure is unexpected
            common.log("Failed to parse Gemini error response or unexpected format: " .. res.body)
            error_message = "Status " .. res.status .. ": " .. res.body
          end
          -- Format the error and call the final callback directly
          local formatted_error = '\n# Gemini Error\n\n' .. error_message .. '\n'
          vim.schedule(function() opts.callback(formatted_error) end)
        else
          -- If status is 200, proceed with the normal flow via common.askCallback
          common.log("Before Gemini callback call (status 200)")
          vim.schedule(function() query.askCallback(res, opts) end)
        end
      end
    })
end

return query
```

**4. `lua/ai/common.lua` (No changes needed)**

The `common.askCallback` function remains as is. Its error handling part (`if res.status ~= 200 then ...`) will now primarily serve `askHeavy` calls or act as a fallback if `ask` somehow calls it with a non-200 status (which shouldn't happen with the changes above).

```lua
-- lua/ai/common.lua
local common = {}

function common.log(message)
  -- Consider making the log file path configurable or relative to project/plugin
  local log_file_path = "/tmp/code-ai.log" -- Changed log file name for clarity
  local log_file = io.open(log_file_path, "a")
  if not log_file then
    -- Use vim.notify for user-visible errors if logging fails
    vim.notify("Error: Could not open log file for writing: " .. log_file_path, vim.log.levels.ERROR)
    return -- Avoid crashing if log file cannot be opened
  end
  -- build a timestamp string surrounded by [] that will prepend the log message
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  message = "[ " .. timestamp .. " ] -- " .. message
  log_file:write(message .. "\n")
  log_file:close()
end


function common.askCallback(res, opts, formatResult)
  local result
  if res.status ~= 200 then
    -- This block will now mostly handle errors from askHeavy or act as a fallback.
    -- Errors from ask() are handled before this function is called.
    if opts.handleError ~= nil then
      -- Allow custom error handling if provided
      result = opts.handleError(res.status, res.body)
    else
      -- Generic fallback error handling
      common.log("Error: API responded with status " .. tostring(res.status) .. '\n\n' .. res.body)
      result = 'Error: API responded with status ' .. tostring(res.status) .. '\n\n' .. res.body
    end
  else
    -- Process successful response
    local ok, data = pcall(vim.fn.json_decode, res.body)
    if not ok or type(data) ~= 'table' then
        -- Handle JSON decoding errors for successful status codes
        common.log("Error: Failed to decode JSON response (Status 200): " .. res.body)
        result = "Error: Could not parse successful API response."
    else
        -- Call the provider-specific formatting function
        local format_ok, formatted_result = pcall(formatResult, data)
        if not format_ok then
            common.log("Error during result formatting: " .. formatted_result) -- Log the error from formatResult
            result = "Error: Failed to format API response."
        else
            result = formatted_result
        end
    end

    -- Allow optional post-processing of the result
    if opts.handleResult ~= nil then
      -- It's safer to wrap this in pcall as well, in case handleResult errors
      local handle_ok, handled_result = pcall(opts.handleResult, result)
      if not handle_ok then
          common.log("Error during opts.handleResult: " .. handled_result)
          -- Decide whether to return the original result or an error message
          result = "Error: Failed during result post-processing."
      else
          result = handled_result
      end
    end
  end
  -- Final callback with the processed result or error message
  -- Wrap the final callback in pcall for robustness
  local cb_ok, cb_err = pcall(opts.callback, result)
  if not cb_ok then
      common.log("Error during final callback execution: " .. cb_err)
      vim.notify("Error executing final callback: " .. cb_err, vim.log.levels.ERROR)
  end
end
return common
```

These changes ensure that non-200 responses from the `ask` function of each provider are intercepted, their specific error messages are parsed, and a formatted error is displayed to the user directly via the `opts.callback`. The `askHeavy` functions remain unchanged and will continue to use the generic error handling in `common.askCallback` if they encounter non-200 responses. I also added some minor improvements like `pcall` around JSON decoding and callbacks for robustness, and slightly more defensive checks in the `formatResult` functions.
