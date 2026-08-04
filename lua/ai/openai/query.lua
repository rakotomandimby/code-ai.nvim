local common = require('ai.common')
local provider = require('ai.provider')

local query = {}

local openai_runner = provider.createQueryRunner({
  name = "OpenAI",
  title_tag = "OPN",
  history_prefix = "openai_",
  api_host = 'https://api.openai.com',
  api_path = '/v1/responses',
  disabled_response = {
    output = {
      { type = "message", role = "assistant", content = { { type = "output_text", text = "" } } },
      { type = "message", role = "assistant", content = { { type = "output_text", text = "OpenAI models are disabled" } } },
    },
    usage = {
      input_tokens = 0,
      output_tokens = 0,
      total_tokens = 0,
    },
  },
  build_headers = function(api_key)
    return {
      ['Content-type'] = 'application/json',
      ['Authorization'] = 'Bearer ' .. api_key,
    }
  end,
  build_request_body = function(model, instruction, prompt)
    local input_messages = {
      {
        role = 'user',
        content = {
          { type = 'input_text', text = prompt }
        }
      }
    }

    local request_body = {
      model = model,
      input = input_messages,
    }

    if instruction and instruction ~= '' then
      request_body.instructions = instruction
    else
      common.log("OpenAI Light mode: No system instructions provided")
    end
    return request_body
  end,
  extract_usage = function(data)
    local usage = type(data.usage) == 'table' and data.usage or {}
    return usage.input_tokens or 0, usage.output_tokens or 0
  end,
  extract_content = function(data)
    local out = {}

    if type(data.output_text) == 'string' and data.output_text ~= '' then
      table.insert(out, data.output_text)
    elseif type(data.output_text) == 'table' then
      for _, s in ipairs(data.output_text) do
        if type(s) == 'string' and s ~= '' then table.insert(out, s) end
      end
    end

    if type(data.output) == 'table' then
      for _, item in ipairs(data.output) do
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

    return table.concat(out, "\n\n")
  end,
  format_error = function(status, body)
    common.log("Formatting OpenAI API error: " .. body)
    local success, error_data = pcall(vim.fn.json_decode, body)

    if success and error_data and error_data.error then
      local error_type = error_data.error.type or "unknown_error"
      local error_message = error_data.error.message or "Unknown error occurred"
      local error_code = error_data.error.code or ""
      local error_param = error_data.error.param or ""

      local error_result = string.format("# OpenAI API Error (%s)\n\n**Error Type**: %s\n", status, error_type)
      if error_code ~= "" then
        error_result = error_result .. string.format("**Error Code**: %s\n", error_code)
      end
      if error_param ~= "" then
        error_result = error_result .. string.format("**Parameter**: %s\n", error_param)
      end
      return error_result .. string.format("**Message**: %s\n", error_message)
    else
      return string.format("# OpenAI API Error (%s)\n\n```\n%s\n```", status, body)
    end
  end
})

function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public, scanned_files)
  openai_runner.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public, scanned_files)
end

function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
  openai_runner.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
end

return query

