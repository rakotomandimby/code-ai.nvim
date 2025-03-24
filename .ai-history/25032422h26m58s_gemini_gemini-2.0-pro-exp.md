# In `query.lua` files, if the model is the "disabled" string, don't query but just return "Model is disabled".

For each of the three `query.lua` files, I want that if the model name is the string "disabled", 
the `ask` and `askHeavy` functions must not perform real query to the model or the agent, 
but should return a JSON that will mwke the plugin to show a message like "Model is disabled".

Tell me the modifications to make to the three `query.lua` files to achieve this.



# This is gemini-2.0-pro-exp answer (10k in, 5k out)

Okay, let's modify the `ask` and `askHeavy` functions in each of the `query.lua` files 
(`lua/ai/anthropic/query.lua`, `lua/ai/chatgpt/query.lua`, and `lua/ai/gemini/query.lua`) 
to handle the "disabled" model case.

Here's the modified code for each file:

**1. `lua/ai/anthropic/query.lua`**

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data)
  common.log("Inside Anthropic formatResult")
  local input_tokens = data.usage.input_tokens or 0  -- Default to 0 for disabled model
  local output_tokens = data.usage.output_tokens or 0 -- Default to 0 for disabled model

  local formatted_input_tokens = string.format("%gk", math.floor(input_tokens / 1000))
  local formatted_output_tokens = string.format("%gk", math.floor(output_tokens / 1000))

  -- Create the result string with token counts
  local result = '\n# This is '.. modelUsed .. ' answer (' .. formatted_input_tokens .. ' in, ' .. formatted_output_tokens .. ' out)\n\n'
  result = result .. data.content[1].text .. '\n\n'
  history.saveToHistory('claude_' .. modelUsed , promptToSave .. '\n\n' .. result)
  return result
end

query.askCallback = function(res, opts)
  common.askCallback(res, opts, query.formatResult)
end

function query.askHeavy(model, instruction, prompt, opts, agent_host)
  promptToSave = prompt
  modelUsed = model

  -- Check if the model is disabled
  if model == "disabled" then
    local disabled_response = {
      content = { { text = "Model is disabled" } },
      usage = { input_tokens = 0, output_tokens = 0 }
    }
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
            vim.schedule(function() query.askCallback(res, opts) end)
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

  -- Check if the model is disabled
  if model == "disabled" then
    local disabled_response = {
      content = { { text = "Model is disabled" } },
      usage = { input_tokens = 0, output_tokens = 0 }
    }
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, opts) end)
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
        vim.schedule(function() query.askCallback(res, opts) end)
      end
    })
end

return query
```

**2. `lua/ai/chatgpt/query.lua`**

```lua
local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data)
  common.log("Inside ChatGPT formatResult")
  local prompt_tokens = data.usage.prompt_tokens or 0 -- Default to 0 for disabled model
  local completion_tokens = data.usage.completion_tokens or 0 -- Default to 0 for disabled model

  local formatted_prompt_tokens = string.format("%gk", math.floor(prompt_tokens / 1000))
  local formatted_completion_tokens = string.format("%gk", math.floor(completion_tokens / 1000))

  -- Create the result string with token counts
  local result = '\n# This is '.. modelUsed .. ' answer (' .. formatted_prompt_tokens .. ' in, ' .. formatted_completion_tokens .. ' out)\n\n'
  result = result .. data.choices[1].message.content .. '\n\n'
  history.saveToHistory('chatgpt_' .. modelUsed , promptToSave .. '\n\n' .. result)
  return result
end

query.askCallback = function(res, opts)
  common.askCallback(res, opts, query.formatResult)
end

function query.askHeavy(model, instruction, prompt, opts, agent_host)
  promptToSave = prompt
  modelUsed = model

  -- Check if model is disabled
  if model == "disabled" then
    local disabled_response = {
      choices = { { message = { content = "Model is disabled" } } },
      usage = { prompt_tokens = 0, completion_tokens = 0 }
    }
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
            vim.schedule(function() query.askCallback(res, opts) end)
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

  -- Check if model is disabled
  if model == "disabled" then
    local disabled_response = {
      choices = { { message = { content = "Model is disabled" } } },
      usage = { prompt_tokens = 0, completion_tokens = 0 }
    }
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, opts) end)
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
        common.log("Before ChatGPT callback call")
        vim.schedule(function() query.askCallback(res, opts) end)
      end
    })
end

return query
```

**3. `lua/ai/gemini/query.lua`**

```lua
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
  local candidates_number = #data['candidates']
  if candidates_number == 1 then
    if data['candidates'][1]['content'] == nil then
      result = '\n#Gemini error\n\nGemini stopped with the reason: ' .. data['candidates'][1]['finishReason'] .. '\n'
      return result
    else
      -- Extract token counts from the response
      local prompt_tokens = data['usageMetadata']['promptTokenCount'] or 0  -- Default to 0
      local answer_tokens = data['usageMetadata']['candidatesTokenCount'] or 0 -- Default to 0

      -- Format token counts (e.g., "30k", "2k")
      local formatted_prompt_tokens = string.format("%gk", math.floor(prompt_tokens / 1000))
      local formatted_answer_tokens = string.format("%gk", math.floor(answer_tokens / 1000))

      result = '\n# This is ' .. modelUsed .. ' answer (' .. formatted_prompt_tokens .. ' in, ' .. formatted_answer_tokens .. ' out)\n\n'
      result = result .. data['candidates'][1]['content']['parts'][1]['text'] .. '\n'
    end
  else
    result = '# There are ' .. candidates_number .. ' Gemini candidates\n'
    for i = 1, candidates_number do
      result = result .. '## Gemini Candidate number ' .. i .. '\n'
      result = result .. data['candidates'][i]['content']['parts'][1]['text'] .. '\n'
    end
  end
  history.saveToHistory('gemini_' .. modelUsed  , promptToSave .. '\n\n' .. result)
  return result
end

query.askCallback = function(res, opts)
    common.askCallback(res, opts, query.formatResult)
end

function query.askHeavy(model, instruction, prompt, opts, agent_host)
  promptToSave = prompt
  modelUsed = model

  -- Check if model is disabled
  if model == "disabled" then
    local disabled_response = {
      candidates = { { content = { parts = { { text = "Model is disabled" } } }, finishReason = "STOP" } },
      usageMetadata = { promptTokenCount = 0, candidatesTokenCount = 0 }
    }
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
            vim.schedule(function() query.askCallback(res, opts) end)
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

  -- Check if model is disabled
  if model == "disabled" then
    local disabled_response = {
      candidates = { { content = { parts = { { text = "Model is disabled" } } }, finishReason = "STOP" } },
      usageMetadata = { promptTokenCount = 0, candidatesTokenCount = 0 }
    }
    vim.schedule(function() query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, opts) end)
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
        common.log("Before gemini callback call")
        vim.schedule(function() query.askCallback(res, opts) end)
      end
    })
end

return query
```

Key changes in all files:

*   **Disabled Model Check:**  Added `if model == "disabled" then ... end` at the beginning of both `ask` and `askHeavy` functions.
*   **Simulated Response:** Inside the `if` block, a `disabled_response` table is created.  This table mimics the structure of a *successful* API response, but contains the "Model is disabled" message.  The structure is tailored to each model's expected response format (very important!).  We also set usage tokens to 0.
*   **Scheduled Callback:**  `vim.schedule(function() query.askCallback(...) end)` is used to simulate the asynchronous nature of the API call.  We call `query.askCallback` with a *fake* `res` object.  The `res` object has a `status` of 200 (to simulate success) and the `body` is the JSON-encoded `disabled_response`.  This is crucial for consistent handling in `common.askCallback`.
*   **Default Token Counts:** In the `formatResult` functions, I've added `or 0` to the `prompt_tokens` and `completion_tokens` (or equivalent) assignments. This handles the case where the "disabled" response might not include these fields, preventing errors.
* **No changes in `common.lua`**: The `common.askCallback` function already correctly handles different status codes, and will correctly process our fake `200` status.

This approach ensures that the rest of your plugin's logic (handling the response, displaying it in the popup, etc.) works seamlessly, even when a model is disabled.  The user gets a clear message, and no actual API calls are made. This is much better than trying to handle the disabled case in `lua/ai/init.lua`, as it keeps the model-specific logic within the model-specific files.

