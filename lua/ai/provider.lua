local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')
local history = require('ai.history')

local M = {}

-- Create a generic query runner for a provider
function M.createQueryRunner(config)
  -- config requires:
  --   name: string (e.g. "Anthropic", "GoogleAI", "OpenAI")
  --   title_tag: string (e.g. "ANT", "GGL", "OPN")
  --   history_prefix: string (e.g. "anthropic_", "googleai_", "openai_")
  --   disabled_response: table
  --   api_host: string
  --   api_path: string
  --   build_headers: function(api_key) -> table
  --   build_request_body: function(model, instruction, prompt) -> table
  --   extract_usage: function(data) -> input_tokens, output_tokens
  --   extract_content: function(data) -> string
  --   format_error: function(status, body) -> string

  local runner = {}

  function runner.formatResult(data, upload_url, upload_token, upload_as_public, opts, model_used, prompt_to_save)
    common.log("Inside " .. config.name .. " formatResult")

    if config.validate_data then
      local err_result = config.validate_data(data)
      if err_result then
        return err_result
      end
    end

    local input_tokens, output_tokens = config.extract_usage(data)
    local formatted_input_tokens = common.formatTokenCount(input_tokens)
    local formatted_output_tokens = common.formatTokenCount(output_tokens)

    local content_text = config.extract_content(data)

    local result = content_text
      .. '\n\n'
      .. config.name .. ' ' .. model_used
      .. ' (' .. formatted_input_tokens .. ' in, ' .. formatted_output_tokens .. ' out)\n\n'

    result = common.insertWordToTitle(config.title_tag, result)

    if model_used ~= 'disabled' then
      history.saveToHistory(config.history_prefix .. model_used, prompt_to_save .. '\n\n' .. result)
      local model_label = config.name .. ' (' .. model_used .. ')'
      common.uploadContent(upload_url, upload_token, result, model_label, upload_as_public)

      if opts and opts.stats then
        common.sendIngestionStats(opts.stats, input_tokens, output_tokens)
        opts.stats = nil
      end
    else
      common.log(config.name .. " model is disabled: skipping history save and upload.")
    end

    return result
  end

  function runner.askCallback(res, opts, model_used, prompt_to_save)
    common.askCallback(
      res,
      {
        handleResult = opts.handleResult,
        handleError = config.format_error,
        callback = opts.callback,
        upload_url = opts.upload_url,
        upload_token = opts.upload_token,
        upload_as_public = opts.upload_as_public,
        stats = opts.stats,
      },
      function(data, upload_url, upload_token, upload_as_public, callback_opts)
        return runner.formatResult(data, upload_url, upload_token, upload_as_public, callback_opts, model_used, prompt_to_save)
      end
    )
  end

  function runner.askHeavy(model, instruction, prompt, opts, api_key, agent_host, upload_url, upload_token, upload_as_public)
    if model == "disabled" then
      common.handleDisabledModel(config.name, model,
        {
          handleResult = opts.handleResult,
          callback = opts.callback,
          upload_url = upload_url,
          upload_token = upload_token,
          upload_as_public = upload_as_public
        },
        function(res, cb_opts)
          runner.askCallback(res, cb_opts, model, prompt)
        end,
        config.disabled_response
      )
      return
    end

    local scanned_files = aiconfig.listScannedFilesFromConfig()
    local project_context = {}

    for _, context in pairs(scanned_files) do
      local content = aiconfig.contentOf(context)
      if content ~= nil then
        table.insert(project_context, { filename = context, content = content })
      end
    end

    local input_size, input_lines = common.calculateInputStats(instruction, prompt, project_context)
    opts.stats = {
      model = model,
      input_size = input_size,
      input_lines = input_lines,
    }

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
        upload_as_public = upload_as_public,
        stats = opts.stats,
      },
      function(res, cb_opts)
        runner.askCallback(res, cb_opts, model, prompt)
      end
    )
  end

  function runner.askLight(model, instruction, prompt, opts, api_key, upload_url, upload_token, upload_as_public)
    if model == "disabled" then
      common.handleDisabledModel(config.name, model,
        {
          handleResult = opts.handleResult,
          callback = opts.callback,
          upload_url = upload_url,
          upload_token = upload_token,
          upload_as_public = upload_as_public
        },
        function(res, cb_opts)
          runner.askCallback(res, cb_opts, model, prompt)
        end,
        config.disabled_response
      )
      return
    end

    local input_size, input_lines = common.calculateInputStats(instruction, prompt, nil)
    opts.stats = {
      model = model,
      input_size = input_size,
      input_lines = input_lines,
    }

    local request_body = config.build_request_body(model, instruction, prompt)
    local headers = config.build_headers(api_key)

    curl.post(config.api_host .. config.api_path, {
      headers = headers,
      body = vim.fn.json_encode(request_body),
      callback = function(res)
        common.log("Before " .. config.name .. " callback call")
        vim.schedule(function()
          runner.askCallback(res, {
            handleResult = opts.handleResult,
            callback = opts.callback,
            upload_url = upload_url,
            upload_token = upload_token,
            upload_as_public = upload_as_public,
            stats = opts.stats,
          }, model, prompt)
        end)
      end
    })
  end

  return runner
end

return M

