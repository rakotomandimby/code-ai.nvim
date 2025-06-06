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

-- START: New function to upload content
function common.uploadContent(url, token, content, model_name)
  if url == '' or token == '' then
    common.log("Upload URL or Token not configured. Skipping upload for " .. model_name .. " response.")
    return
  end

  common.log("Attempting to upload " .. model_name .. " response to: " .. url)
  common.log(content)
  common.log("====================================================")

  local headers = {
    ['Content-Type'] = 'text/markdown',
    ['X-MarkdownBlog-Token'] = token
  }

  -- if model_name is not the string "disabled", then upload the content
  if model_name ~= 'disabled' then
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
    return
  end
end
-- END: New function to upload content


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
    -- Pass upload_url and upload_token to formatResult
    result = formatResult(data, opts.upload_url, opts.upload_token) -- Modified: Pass upload options
    if opts.handleResult ~= nil then
      result = opts.handleResult(result)
    end
  end
  opts.callback(result)
end
return common


