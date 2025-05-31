# What is the behaviour of the code if no agent host is set and no system instructions file is found?

I would like to know the behavior of the code when no `xxx_agent_host` is set and no system instructions file (`.ai-system-instructions.md`) is found.
Specifically, what happens in that case?





# This is gemini-2.5-pro-preview-05-06 answer (14k in, 1k out)

Okay, let's trace the execution flow when no `xxx_agent_host` options are set and no `.ai-system-instructions.md` file is found.

**1. System Instructions Retrieval:**

*   In `lua/ai/init.lua`, the `M.handle` function starts by trying to get system instructions:
    ```lua
    local instruction = aiconfig.getSystemInstructions()
    ```
*   This calls `aiconfig.getSystemInstructions()` in `lua/ai/aiconfig.lua`:
    ```lua
    function aiconfig.getSystemInstructions()
      local path = aiconfig.findSystemInstructionsFile()
      if path == "" then
        return "" -- No file found, returns an empty string
      end
      -- ... (reads file content if found)
    end
    ```
*   `aiconfig.findSystemInstructionsFile()` looks for `.ai-system-instructions.md` in the current working directory. If it's not found:
    ```lua
    function aiconfig.findSystemInstructionsFile()
      local path = vim.fn.getcwd() .. '/.ai-system-instructions.md'
      local file = io.open(path, "r")
      if file ~= nil then
        -- ...
      else
        return "" -- File not found, returns an empty string
      end
    end
    ```
*   So, if `.ai-system-instructions.md` is not present, `instruction` in `M.handle` will be an empty string (`""`).

**2. Agent Host Check:**

*   Still in `M.handle` (`lua/ai/init.lua`), the code checks if agent hosts are configured:
    ```lua
    local use_anthropic_agent = M.opts.anthropic_agent_host ~= ''
    local use_googleai_agent = M.opts.googleai_agent_host ~= ''
    local use_openai_agent = M.opts.openai_agent_host ~= ''
    ```
*   If `M.opts.anthropic_agent_host`, `M.opts.googleai_agent_host`, and `M.opts.openai_agent_host` are all empty strings (i.e., not set), then `use_anthropic_agent`, `use_googleai_agent`, and `use_openai_agent` will all be `false`.

**3. Determining API Call Type (Direct vs. Agent):**

*   The code then decides whether to use direct API calls or agent-based calls (`askHeavy`):
    ```lua
    if (number_of_files == 0
          or not use_anthropic_agent
          or not use_googleai_agent
          or not use_openai_agent) then
      common.log("Not using agents")
      anthropic.ask(
        anthropic_model,
        instruction, -- This will be ""
        prompt,
        askHandleResultAndCallbackAnthropic,
        M.opts.anthropic_api_key)
      googleai.ask(
        googleai_model,
        instruction, -- This will be ""
        prompt,
        askHandleResultAndCallbackGoogleAI,
        M.opts.googleai_api_key)
      openai.ask(
        openai_model,
        instruction, -- This will be ""
        prompt,
        askHandleResultAndCallbackOpenAI,
        M.opts.openai_api_key)
    else
      common.log("Using agents")
      -- Calls anthropic.askHeavy, googleai.askHeavy, openai.askHeavy
    end
    ```
*   Since `use_anthropic_agent`, `use_googleai_agent`, and `use_openai_agent` are all `false`, the condition `(not use_anthropic_agent or not use_googleai_agent or not use_openai_agent)` evaluates to `(true or true or true)`, which is `true`.
*   Therefore, the code will enter the `if` block and make direct API calls using `anthropic.ask`, `googleai.ask`, and `openai.ask`. The `instruction` variable passed to these functions will be the empty string (`""`) obtained in step 1.

**4. Popup Creation:**

*   Before making the API calls, a popup is created. The content of this initial popup also depends on the agent host flags:
    ```lua
    if (number_of_files == 0 or not use_anthropic_agent or not use_googleai_agent or not use_openai_agent ) then
      update = M.createPopup(M.fill(def.loading_tpl , args), width - 8, height - 4)
    else
      local scanned_files = aiconfig.listScannedFilesAsFormattedTable()
      update = M.createPopup(M.fill(def.loading_tpl .. scanned_files, args), width - 8, height - 4)
    end
    ```
*   Since the agent flags are `false`, the first branch is taken. The popup will be created with the content of `def.loading_tpl` (e.g., "Loading..."). It will **not** include the table of scanned files in the initial loading message.

**5. Behavior of `ask` functions with empty `instruction`:**

*   **`anthropic.ask` (`lua/ai/anthropic/query.lua`):**
    The `system` parameter in the JSON body sent to the Anthropic API will be `""`. Anthropic's API is designed to handle an empty system prompt. The model will rely on its default behavior and the user prompt.
    ```lua
    body = vim.fn.json_encode(
      {
        model = model,
        max_tokens = 8192,
        system = instruction, -- instruction is ""
        messages = -- ... user prompt ...
      }
    )
    ```

*   **`googleai.ask` (`lua/ai/googleai/query.lua`):**
    The `system_instruction.parts.text` in the JSON body sent to the Google AI API will be `""`. The Gemini API also handles empty system instructions gracefully.
    ```lua
    body = vim.fn.json_encode(
      {
        system_instruction = {parts = {text = instruction}}, -- instruction is ""
        contents = -- ... user prompt ...
      }
    )
    ```

*   **`openai.ask` (`lua/ai/openai/query.lua`):**
    For standard chat models (not starting with `o1`), a system message with empty content will be sent: `{ role = 'system', content = "" }`. OpenAI's API handles this by not applying any specific system-level instructions beyond the model's default pre-prompting.
    ```lua
    messages = (function()
      local messages = {}
      if string.sub(model, 1, 2) == 'o1' then
        -- ... (legacy case, instruction would be prepended to prompt)
      else
        table.insert(messages, { role = 'system', content = instruction }) -- instruction is ""
        table.insert(messages, {role = 'user', content = prompt})
      end
      return messages
    end)()
    ```

**In summary:**

If no agent hosts are set and no `.ai-system-instructions.md` file is found:
1.  The `instruction` variable will be an empty string.
2.  The plugin will **not** use the `askHeavy` functions (which are intended for agent-based interaction with file context).
3.  It will make direct API calls to Anthropic, GoogleAI, and OpenAI using their respective `ask` functions.
4.  The system prompt/instruction sent to each API will be empty.
5.  The AI models will respond based on their default behavior and the user-provided prompt, without any custom system-level guidance from a file.
6.  The initial loading popup will display the standard loading message without the table of scanned files.

The plugin handles this scenario gracefully by falling back to a more basic interaction mode with the AI providers.
