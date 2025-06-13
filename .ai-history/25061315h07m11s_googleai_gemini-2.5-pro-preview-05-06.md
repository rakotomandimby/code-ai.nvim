# Use native lua functions to log messages

I face those errors when using this plugin:

```
Error executing callback:
lua/ai/common.lua:13: E5560: Vimscript function must not be called in a fast event context
stack traceback:
        [C]: in function 'writefile'
lua/ai/common.lua:13: in function 'log'
lua/ai/common.lua:46: in function '_user_on_exit'
```

My codebase uses vim builtin functions to performs filesystem operations.
I think this is an error to do that everywhere, so I want to use native lua functions instead in this `log` function.

Tell me the whole new content of common.lua file, using native lua functions to log messages.




# GGL Refactor `common.log` to use native Lua I/O functions

We will modify the `common.log` function in `lua/ai/common.lua` to use Lua's native file I/O operations (`io.open`, `file:write`, `file:close`) instead of `vim.fn.writefile`. This change aims to resolve errors related to calling Vimscript functions in fast event contexts. The new implementation will open the log file in append mode, write the formatted log message (ensuring a newline is added), and then close the file. Error handling will be maintained, falling back to `vim.api.nvim_err_writeln` if Lua I/O operations fail.

## `lua/ai/common.lua`

```lua
local common = {}
local curl = require('plenary.curl') -- Added curl dependency for upload

function common.log(message)
  local log_path = "/tmp/aiconfig.log"
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  -- Ensure a newline character is appended for Lua's file:write
  local full_log_message = "[ " .. timestamp .. " ] -- " .. message .. "\n"

  local file, err_open = io.open(log_path, "a") -- Open in append mode ("a")
  if not file then
    -- If opening the file fails, print an error to Neovim's message area.
    -- Avoid using common.log here to prevent potential recursion.
    vim.api.nvim_err_writeln("Error: Could not open log file " .. log_path .. " for appending: " .. tostring(err_open))
    return
  end

  local ok, err_write = file:write(full_log_message)
  if not ok then
    -- If writing to the file fails, print an error.
    vim.api.nvim_err_writeln("Error: Could not write to log file " .. log_path .. ": " .. tostring(err_write))
  end

  file:close()
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

```

GoogleAI gemini-2.5-pro-preview-05-06 (18k in, 1k out)


