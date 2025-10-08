local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local query = {}
local history = require('ai.history')

local promptToSave = ""
local modelUsed = ""

function query.formatResult(data, upload_url, upload_token, upload_as_public)
  common.log("Inside GoogleAI formatResult")
  
  local result = ''
  local candidates_number = #data['candidates']
  
  if candidates_number == 1 then
    if data['candidates'][1]['content'] == nil then
      result = '\n#GoogleAI error\n\nGoogleAI stopped with the reason: ' 
        .. data['candidates'][1]['finishReason'] .. '\n'
      return result
    else
      local prompt_tokens = data['usageMetadata']['promptTokenCount'] or 0
      local answer_tokens = data['usageMetadata']['candidatesTokenCount'] or 0

      local formatted_prompt_tokens = common.formatTokenCount(prompt_tokens)
      local formatted_answer_tokens = common.formatTokenCount(answer_tokens)

      result = data['candidates'][1]['content']['parts'][1]['text'] 
        .. '\n\n' 
        .. 'GoogleAI ' .. modelUsed 
        .. ' (' .. formatted_prompt_tokens .. ' in, ' .. formatted_answer_tokens .. ' out)\n\n'
    end
  else
    result = '# There are ' .. candidates_number .. ' GoogleAI candidates\n'
    for i = 1, candidates_number do
      result = result .. '## GoogleAI Candidate number ' .. i .. '\n'
      result = result .. data['candidates'][i]['content']['parts'][1]['text'] .. '\n'
    end
  end
  
  result = common.insertWordToTitle('GGL', result)
  history.saveToHistory('googleai_' .. modelUsed, promptToSave .. '\n\n' .. result)

  common.uploadContent(upload_url, upload_token, result, 'GoogleAI (' .. modelUsed .. ')', upload_as_public)

  return result
end

function query.formatError(status, body)
  common.log("Formatting GoogleAI API error: " .. body)
  local error_result
  local success, error_data = pcall(vim.fn.json_decode, body)
  
  if success and error_data and error_data.error then
    local error_code = error_data.error.code or status
    local error_message = error_data.error.message or "Unknown error occurred"
    local error_status = error_data.error.status or "ERROR"
    error_result = string.format(
      "# GoogleAI API Error (%s)\n\n**Error Code**: %s\n**Status**: %s\n**Message**: %s\n",
      status,
      error_code,
      error_status,
      error_message
    )
  else
    error_result = string.format("# GoogleAI API Error (%s)\n\n```\n%s\n```", status, body)
  end
  return error_result
end

query.askCallback = function(res, opts)
  local handleError = query.formatError
  common.askCallback(
    res,
    {
      handleResult = opts.handleResult,
      handleError = handleError,
      callback = opts.callback,
      upload_url = opts.upload_url,
      upload_token = opts.upload_token,
      upload_as_public = opts.upload_as_public
    },
    query.formatResult
  )
end

local disabled_response = {
  candidates = { { content = { parts = { { text = "GoogleAI models are disabled" } } }, finishReason = "STOP" } },
  usageMetadata = { promptTokenCount = 0, candidatesTokenCount = 0 }
}

function query.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    common.handleDisabledModel('GoogleAI', model,
      {
        handleResult = opts.handleResult,
        callback = opts.callback,
        upload_url = upload_url,
        upload_token = upload_token,
        upload_as_public = upload_as_public
      },
      query.askCallback,
      disabled_response
    )
    return
  end

  local scanned_files = aiconfig.listScannedFilesFromConfig()
  local project_context = {}
  
  for _, context in pairs(scanned_files) do
    local content = aiconfig.contentOf(context)
    if content ~= nil then
      table.insert(project_context, {filename = context, content = content})
    end
  end

  common.askHeavy(
    agent_host,
    api_key,
    model,
    instruction,
    prompt,
    project_context,
    {
      handleResult = opts.handleResult,
      callback = opts.callback,
      upload_url = upload_url,
      upload_token = upload_token,
      upload_as_public = upload_as_public
    },
    query.askCallback
  )
end

function query.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
  promptToSave = prompt
  modelUsed = model

  if model == "disabled" then
    common.handleDisabledModel('GoogleAI', model,
      {
        handleResult = opts.handleResult,
        callback = opts.callback,
        upload_url = upload_url,
        upload_token = upload_token,
        upload_as_public = upload_as_public
      },
      query.askCallback,
      disabled_response
    )
    return
  end

  local api_host = 'https://generativelanguage.googleapis.com'
  local path = '/v1beta/models/' .. model .. ':generateContent'
  
  curl.post(api_host .. path, {
    headers = {
      ['Content-type'] = 'application/json',
      ['x-goog-api-key'] = api_key
    },
    body = vim.fn.json_encode({
      system_instruction = {parts = {text = instruction}},
      contents = {{role = 'user', parts = {{text = prompt}}}},
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
      vim.schedule(function()
        query.askCallback(res, {
          handleResult = opts.handleResult,
          callback = opts.callback,
          upload_url = upload_url,
          upload_token = upload_token,
          upload_as_public = upload_as_public
        })
      end)
    end
  })
end

return query

