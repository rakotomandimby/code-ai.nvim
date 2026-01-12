local common = {}
local curl = require('plenary.curl')

function common.log(message)
  local log_path = "/tmp/aiconfig.log"
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local full_log_message = "[ " .. timestamp .. " ] -- " .. message .. "\n"

  local file, err = io.open(log_path, "a")
  if not file then
    pcall(function()
      vim.api.nvim_echo({ { "Error: Could not open log file: " .. log_path .. " - " .. (err or "unknown error"), "ErrorMsg" } }, false, {})
    end)
    return
  end

  file:write(full_log_message)
  file:close()
end

local function json_encode(v)
  return vim.json.encode(v)
end

function common.uploadContent(url, token, content, model_name, is_public)
  if url == '' or token == '' then
    common.log("Upload URL or Token not configured. Skipping upload for " .. model_name .. " response.")
    return
  end

  if model_name ~= 'disabled' then
    common.log("Attempting to upload " .. model_name .. " response to: " .. url)

    local headers = {
      ['Content-Type'] = 'text/markdown',
      ['X-MarkdownBlog-Token'] = token
    }
    if is_public == true then
      headers['X-MarkdownBlog-Public'] = 'true'
      common.log("Setting upload as public for " .. model_name)
    end

    common.log("Uploading content for model: " .. model_name)
    curl.put(url,
      {
        headers = headers,
        body = content,
        timeout = 500000,
        callback = function(res)
          if res.status >= 200 and res.status < 300 then
            common.log("Successfully uploaded " .. model_name .. " response. Status: " .. res.status)
          else
            common.log("Failed to upload " .. model_name .. " response. Status: " .. res.status .. ", Body: " .. res.body)
          end
        end
      })
  else
    common.log("Model is disabled. Skipping upload.")
  end
end

function common.askCallback(res, opts, formatResult)
  local result
  if res.status ~= 200 then
    if opts.handleError ~= nil then
      result = opts.handleError(res.status, res.body)
    else
      common.log("Error: API responded with the status " .. tostring(res.status) .. '\n\n' .. res.body)
      result = 'Error: API responded with the status ' .. tostring(res.status) .. '\n\n' .. res.body
    end
  else
    local data = vim.fn.json_decode(res.body)
    result = formatResult(data, opts.upload_url, opts.upload_token, opts.upload_as_public)
    if opts.handleResult ~= nil then
      result = opts.handleResult(result)
    end
  end
  opts.callback(result)
end

function common.insertWordToTitle(word_to_insert, text)
  local lines = vim.split(text, '\n', { plain = true })
  if #lines == 0 then
    return text
  end

  if lines[1]:sub(1, 1) == '#' then
    lines[1] = lines[1]:gsub('^# ', '# ' .. word_to_insert .. ' ')
  else
    lines[1] = '# ' .. word_to_insert .. ' ' .. lines[1]
  end

  return table.concat(lines, '\n')
end

function common.formatTokenCount(count)
  if type(count) ~= 'number' then
    count = tonumber(count) or 0
  end

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

-- Handle disabled model response
function common.handleDisabledModel(provider_name, model_name, opts, askCallback, disabled_response)
  vim.schedule(function()
    askCallback(
      { status = 200, body = json_encode(disabled_response) },
      {
        handleResult = opts.handleResult,
        callback = opts.callback,
        upload_url = opts.upload_url or '',
        upload_token = opts.upload_token or '',
        upload_as_public = opts.upload_as_public or false
      }
    )
  end)
end

-- Generic heavy query implementation with iterative state machine for data persistence
function common.askHeavy(agent_host, api_key, model, instruction, prompt, project_context, opts, askCallback)
  local url = agent_host .. '/'
  local body_chunks = {}

  -- Prepare the sequence of data to be stored
  table.insert(body_chunks, { type = 'api key', text = api_key })
  table.insert(body_chunks, { type = 'system instructions', text = instruction })
  table.insert(body_chunks, { type = 'model', text = model })

  for _, context in pairs(project_context) do
    if context.content ~= nil then
      table.insert(body_chunks, { type = 'file', filename = context.filename, content = context.content })
    end
  end

  -- The final chunk is the prompt which triggers the LLM call
  table.insert(body_chunks, { type = 'prompt', text = prompt })

  -- State machine variables
  local current_index = 0
  local total_chunks = #body_chunks
  local failed = false

  common.log(string.format("askHeavy: Starting to send %d chunks to %s", total_chunks, url))

  -- Iterative function to send the next chunk
  local function sendNextChunk()
    -- Check if we've already failed or completed
    if failed then
      common.log("askHeavy: Skipping chunk sending due to previous failure")
      return
    end

    current_index = current_index + 1

    if current_index > total_chunks then
      common.log("askHeavy: All chunks sent successfully")
      return
    end

    local current_chunk = body_chunks[current_index]
    local is_last = (current_index == total_chunks)
    local chunk_type = current_chunk.type
    local chunk_identifier = chunk_type
    if chunk_type == 'file' then
      chunk_identifier = chunk_type .. ':' .. (current_chunk.filename or 'unknown')
    end

    common.log(string.format("askHeavy: Sending chunk %d/%d: %s", current_index, total_chunks, chunk_identifier))

    -- Use pcall to catch synchronous errors from curl.post
    local success, err = pcall(function()
      curl.post(url, {
        headers = { ['Content-type'] = 'application/json' },
        body = json_encode(current_chunk),
        timeout = 30000,
        callback = function(res)
          -- Log the response status
          local response_status = res.status or 'nil'
          local response_body_preview = ''
          if res.body and #res.body > 0 then
            response_body_preview = string.sub(res.body, 1, 100)
            if #res.body > 100 then
              response_body_preview = response_body_preview .. '...'
            end
          end
          common.log(string.format("askHeavy: Received response for chunk %d/%d (%s): status=%s, body=%s",
            current_index, total_chunks, chunk_identifier, tostring(response_status), response_body_preview))

          -- If a configuration chunk fails, we stop the process and notify the user
          if res.status ~= 200 then
            failed = true
            local error_msg = string.format("Failed to store %s (chunk %d/%d). Agent returned status %s: %s",
              chunk_identifier, current_index, total_chunks, tostring(res.status), res.body or "No response body")

            common.log("askHeavy: ERROR - " .. error_msg)
            vim.schedule(function()
              opts.callback("# Agent Error\n\n" .. error_msg)
            end)
            return
          end

          if is_last then
            -- Process the final LLM response
            common.log(string.format("askHeavy: Final chunk (prompt) processed successfully, invoking askCallback"))
            vim.schedule(function()
              askCallback(res, {
                handleResult = opts.handleResult,
                callback = opts.callback,
                upload_url = opts.upload_url,
                upload_token = opts.upload_token,
                upload_as_public = opts.upload_as_public
              })
            end)
          else
            -- Schedule the next chunk on Neovim's event loop with a small delay
            -- This prevents stack overflow and allows the event loop to breathe
            common.log(string.format("askHeavy: Scheduling next chunk %d/%d", current_index + 1, total_chunks))
            vim.defer_fn(function()
              sendNextChunk()
            end, 3)
          end
        end
      })
    end)

    if not success then
      failed = true
      local error_msg = string.format("Exception while sending chunk %d/%d (%s): %s",
        current_index, total_chunks, chunk_identifier, tostring(err))
      common.log("askHeavy: EXCEPTION - " .. error_msg)
      vim.schedule(function()
        opts.callback("# Agent Error\n\n" .. error_msg)
      end)
    end
  end

  -- Start the iterative upload by scheduling the first chunk
  vim.defer_fn(function()
    sendNextChunk()
  end, 3)
end

return common
