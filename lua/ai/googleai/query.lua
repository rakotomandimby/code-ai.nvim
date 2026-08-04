local common = require('ai.common')
local provider = require('ai.provider')

local query = {}

local googleai_runner = provider.createQueryRunner({
  name = "GoogleAI",
  title_tag = "GGL",
  history_prefix = "googleai_",
  api_host = 'https://generativelanguage.googleapis.com',
  api_path = '/v1beta/interactions',
  disabled_response = {
    steps = { { type = "model_output", content = { { text = "GoogleAI models are disabled" } } } },
    usage = { total_input_tokens = 0, total_output_tokens = 0 }
  },
  build_headers = function(api_key)
    return {
      ['Content-type'] = 'application/json',
      ['x-goog-api-key'] = api_key
    }
  end,
  build_request_body = function(model, instruction, prompt)
    local request_body = {
      model = model,
      input = prompt,
      generation_config = {
        temperature = 0.2,
        top_p = 0.5
      }
    }
    if instruction and instruction ~= '' then
      request_body.system_instruction = instruction
    else
      common.log("GoogleAI Light mode: No system instructions provided")
    end
    return request_body
  end,
  validate_data = function(data)
    local steps = data['steps']
    if steps == nil or #steps == 0 then
      if data['error'] then
        return '\n#GoogleAI error\n\nGoogleAI stopped with the reason: '
          .. (data['error']['message'] or 'unknown') .. '\n'
      else
        return '\n#GoogleAI error\n\nUnknown error or empty response.\n'
      end
    end

    local last_output = nil
    for i = #steps, 1, -1 do
      if steps[i].type == "model_output" then
        last_output = steps[i]
        break
      end
    end

    if not last_output or not last_output.content or #last_output.content == 0 then
      return '\n#GoogleAI error\n\nNo model output found.\n'
    end

    return nil
  end,
  extract_usage = function(data)
    local usage = data.usage or {}
    return usage.total_input_tokens or 0, usage.total_output_tokens or 0
  end,
  extract_content = function(data)
    local steps = data['steps'] or {}
    for i = #steps, 1, -1 do
      if steps[i].type == "model_output" and steps[i].content and steps[i].content[1] then
        return steps[i].content[1].text or ""
      end
    end
    return ""
  end,
  format_error = function(status, body)
    common.log("Formatting GoogleAI API error: " .. body)
    local success, error_data = pcall(vim.fn.json_decode, body)

    if success and error_data and error_data.error then
      local error_code = error_data.error.code or status
      local error_message = error_data.error.message or "Unknown error occurred"
      local error_status = error_data.error.status or "ERROR"
      return string.format(
        "# GoogleAI API Error (%s)\n\n**Error Code**: %s\n**Status**: %s\n**Message**: %s\n",
        status,
        error_code,
        error_status,
        error_message
      )
    else
      return string.format("# GoogleAI API Error (%s)\n\n```\n%s\n```", status, body)
    end
  end
})

function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public)
  googleai_runner.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public)
end

function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
  googleai_runner.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
end

return query

