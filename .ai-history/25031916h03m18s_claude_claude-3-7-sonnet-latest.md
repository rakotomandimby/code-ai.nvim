# Having system instruction in a `.ai-system-instructions.md` file.

Currently, system instructions are given in command definition.

I want to change that: I want to have a `.ai-system-instructions.md` file that contains all the system instructions.

The system instructions file will be located in the same directory as the `.ai-prompts.md` file.

We will have to remove givin the system instructions in the command definition.

Tell me the modifications I have to make to the code in order to implement this feature.




# This is claude-3-7-sonnet-latest answer (10k in, 1k out)

# Adding System Instructions in a `.ai-system-instructions.md` File

To implement this feature, you need to modify your codebase to read system instructions from a `.ai-system-instructions.md` file instead of directly from command definitions. Here's how to make these changes:

## 1. First, Add Function to Read System Instructions in `aiconfig.lua`

Add the following function to `lua/ai/aiconfig.lua`:

```lua
function aiconfig.findSystemInstructionsFile()
  local path = vim.fn.getcwd() .. '/.ai-system-instructions.md'
  local file = io.open(path, "r")
  if file ~= nil then
    io.close(file)
    return path
  else
    return ""
  end
end

function aiconfig.getSystemInstructions()
  local path = aiconfig.findSystemInstructionsFile()
  if path == "" then
    return ""
  end
  
  local file = io.open(path, "r")
  if not file then
    return ""
  end
  
  local content = file:read("*all")
  file:close()
  return content
end
```

## 2. Modify `init.lua` to Use System Instructions from File

In `lua/ai/init.lua`, update the `M.handle` function to use system instructions from the file if available:

```lua
function M.handle(name, input)
  local def = M.prompts[name]
  local width = vim.fn.winwidth(0)
  local height = vim.fn.winheight(0)
  local args = {
    locale = M.opts.locale,
    alternate_locale = M.opts.alternate_locale,
    input = input,
    input_encoded = vim.fn.json_encode(input),
  }

  local number_of_files = #aiconfig.listScannedFilesFromConfig()
  local use_anthropic_agent = M.opts.anthropic_agent_host ~= ''
  local use_gemini_agent = M.opts.gemini_agent_host ~= ''
  local use_chatgpt_agent = M.opts.chatgpt_agent_host ~= ''

  local update = nil

  if (number_of_files == 0 or not use_anthropic_agent or not use_gemini_agent or not use_chatgpt_agent ) then
    update = M.createPopup(M.fill(def.loading_tpl , args), width - 8, height - 4)
  else
    local scanned_files = aiconfig.listScannedFiles()
    update = M.createPopup(M.fill(def.loading_tpl .. scanned_files, args), width - 8, height - 4)
  end
  local prompt = M.fill(def.prompt_tpl, args)
  
  -- Get system instructions from file or fall back to command definition
  local system_instructions = aiconfig.getSystemInstructions()
  local instruction = system_instructions ~= "" and system_instructions or M.fill(def.instruction_tpl, args)

  -- Rest of the function remains the same...
```

## 3. Update Default Prompts to Remove Instruction Templates

Remove the `instruction_tpl` from the default prompts in `lua/ai/init.lua`:

```lua
local default_prompts = {
  introduce = {
    command = 'AIIntroduceYourself',
    loading_tpl = 'Loading...',
    prompt_tpl = 'Say who you are, your version, and the currently used model',
    -- instruction_tpl is removed as it will now come from file
    result_tpl = '${output}',
    require_input = false,
  }
}
```

## 4. Add Command to Create/Edit System Instructions File

Add a new command in the `setup` function of `lua/ai/init.lua`:

```lua
function M.setup(opts)
  -- Existing code...
  
  vim.api.nvim_create_user_command('AIEditSystemInstructions', function()
    local path = aiconfig.findSystemInstructionsFile()
    if path == "" then
      path = vim.fn.getcwd() .. '/.ai-system-instructions.md'
      -- Create the file with a default template
      local file = io.open(path, "w")
      if file then
        file:write("# AI System Instructions\n\nAct as a helpful assistant with expertise in programming and software development.\n")
        file:close()
      end
    end
    -- Open the file in a new buffer
    vim.cmd('edit ' .. path)
  end, {})
  
  -- Existing code...
end
```

## 5. Add File Check Logic in All Query Files

Modify each query file (`lua/ai/anthropic/query.lua`, `lua/ai/gemini/query.lua`, and `lua/ai/chatgpt/query.lua`) to support the system instructions file:

For example, in `lua/ai/anthropic/query.lua`, modify the `ask` function:

```lua
function query.ask(model, instruction, prompt, opts, api_key)
  promptToSave = prompt
  modelUsed = model
  local api_host = 'https://api.anthropic.com'
  -- local api_host = 'https://eowloffrpvxwtqp.m.pipedream.net'
  local path = '/v1/messages'
  curl.post(api_host .. path,
    {
      headers = {
        ['Content-type'] = 'application/json',
        ['x-api-key'] = api_key,
        ['anthropic-version'] = '2023-06-01'
      },
      body = vim.fn.json_encode(
        {
          model = model,
          max_tokens = 8192,
          system = instruction,
          messages = (function()
            local messages = {}
            table.insert(messages, {role = 'user', content = prompt})
            return messages
          end)()
        }
      ),
      callback = function(res)
        common.log("Before Anthropic callback call")
        vim.schedule(function() query.askCallback(res, opts) end)
      end
    })
end
```

Similarly, update the `askHeavy` function in all query files to pass the system instructions from the file.

## 6. Add Logging for System Instructions

In the `common.lua` file, add a log message when system instructions are loaded:

```lua
-- Add this somewhere appropriate in the code flow
common.log("System instructions: " .. (aiconfig.getSystemInstructions() ~= "" and "loaded from file" or "using default"))
```

## Complete Implementation

With these changes, your plugin will:

1. Look for a `.ai-system-instructions.md` file in the project root
2. If found, use its contents as system instructions for all AI models
3. If not found, fall back to any instruction_tpl defined in the command
4. Provide a command to create and edit the system instructions file

This implementation maintains backward compatibility while adding the new feature of centralized system instructions.

