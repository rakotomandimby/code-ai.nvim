local common = {}
local curl = require('plenary.curl') -- Added curl dependency for upload

function common.log(message)
  local log_file = io.open("/tmp/aiconfig.log", "a")
  if not log_file then
    error("Could not open log file for writing.")
  end
  -- build a timestamp string surrounded by [] that will prepend the log message
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  message = "[ " .. timestamp .. " ] -- " .. message
  log_file:write(message .. "\n")
  log_file:close()
end

function common.uploadContent(url, token, content, model_name, is_public)
  if url == '' or token == '' then
    common.log("Upload URL or Token not configured. Skipping upload for " .. model_name .. " response.")
    return -- Early return if not configured
  end

  if model_name ~= 'disabled' then
    common.log("Attempting to upload " .. model_name .. " response to: " .. url)

    local headers = {
      ['Content-Type'] = 'text/markdown',
      ['X-MarkdownBlog-Token'] = token
    }
    -- Add public header if upload_as_public is true
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
    -- Pass upload_url, upload_token, and upload_as_public to formatResult
    result = formatResult(data, opts.upload_url, opts.upload_token, opts.upload_as_public) -- Modified: Pass upload_as_public option
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

  -- Check if the first line starts with a title
  if lines[1]:sub(1, 1) == '#' then
    -- Insert the word at the beginning of the first line
    lines[1] = lines[1]:gsub('^# ', '# ' .. word_to_insert .. ' ')
  else
    -- Prepend a new title with the word
    lines[1] = '# ' .. word_to_insert .. ' ' .. lines[1]
  end

  return table.concat(lines, '\n')
end

return common
