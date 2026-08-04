local common = require('ai.common')
local provider = require('ai.provider')

local query = {}

local anthropic_runner = provider.createQueryRunner({
  name = "Anthropic",
  title_tag = "ANT",
  history_prefix = "anthropic_",
  api_host = 'https://api.anthropic.com',
  api_path = '/v1/messages',
  disabled_response = {
    content = { { text = "Anthropic models are disabled" } },
    usage = { input_tokens = 0, output_tokens = 0 }
  },
  build_headers = function(api_key)
    return {
      ['Content-type'] = 'application/json',
      ['x-api-key'] = api_key,
      ['anthropic-version'] = '2023-06-01'
    }
  end,
  build_request_body = function(model, instruction, prompt)
    local request_body = {
      model = model,
      max_tokens = 64000,
      messages = { { role = 'user', content = prompt } }
    }
    if instruction and instruction ~= '' then
      request_body.system = instruction
    else
      common.log("Anthropic Light mode: No system instructions provided")
    end
    return request_body
  end,
  extract_usage = function(data)
    local usage = data.usage or {}
    return usage.input_tokens or 0, usage.output_tokens or 0
  end,
  extract_content = function(data)
    if data.content and data.content[1] and data.content[1].text then
      return data.content[1].text
    end
    return ""
  end,
  format_error = function(status, body)
    common.log("Formatting Anthropic API error: " .. body)
    local success, error_data = pcall(vim.fn.json_decode, body)

    if success and error_data and error_data.error then
      local error_type = error_data.error.type or "unknown_error"
      local error_message = error_data.error.message or "Unknown error occurred"
      return string.format(
        "# Anthropic API Error (%s)\n\n**Error Type**: %s\n**Message**: %s\n",
        status,
        error_type,
        error_message
      )
    else
      return string.format("# Anthropic API Error (%s)\n\n```\n%s\n```", status, body)
    end
  end
})

function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public, scanned_files)
  anthropic_runner.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public, scanned_files)
end

function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
  anthropic_runner.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
end

return query

