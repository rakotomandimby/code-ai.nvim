local common = {}
local curl = require('plenary.curl')

function common.log(message)
  local log_path = "/tmp/aiconfig.log"
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local full_log_message = "[ " .. timestamp .. " ] -- " .. message .. "\n"

  local file, err = io.open(log_path, "a")
  if not file then
    pcall(function()
      vim.api.nvim_echo({{"Error: Could not open log file: " .. log_path .. " - " .. (err or "unknown error"), "ErrorMsg"}}, false, {})
    end)
    return
  end
  
  file:write(full_log_message)
  file:close()
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
      { status = 200, body = vim.json.encode(disabled_response) },
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

-- Generic heavy query implementation
function common.askHeavy(agent_host, api_key, model, instruction, prompt, project_context, opts, askCallback)
  local url = agent_host .. '/'
  local body_chunks = {}
  
  table.insert(body_chunks, {type = 'api key', text = api_key})
  table.insert(body_chunks, {type = 'system instructions', text = instruction})
  table.insert(body_chunks, {type = 'model', text = model})
  
  for _, context in pairs(project_context) do
    if context.content ~= nil then
      table.insert(body_chunks, {type = 'file', filename = context.filename, content = context.content})
    end
  end
  
  table.insert(body_chunks, {type = 'prompt', text = prompt})

  -- Send all chunks except the last without waiting
  for i = 1, #body_chunks - 1 do
    local message = body_chunks[i]
    local body = vim.json.encode(message)
    curl.post(url, {
      headers = {['Content-type'] = 'application/json'},
      body = body,
      callback = function(res) end
    })
  end

  -- Send the last chunk and wait for response
  local last_message = body_chunks[#body_chunks]
  local body = vim.json.encode(last_message)

  curl.post(url, {
    headers = {['Content-type'] = 'application/json'},
    body = body,
    callback = function(res)
      vim.schedule(function()
        askCallback(res, {
          handleResult = opts.handleResult,
          callback = opts.callback,
          upload_url = opts.upload_url,
          upload_token = opts.upload_token,
          upload_as_public = opts.upload_as_public
        })
      end)
    end
  })
end

return common

