# Scope of `append_embeded_system_instructions`

I just added a new configuration option `append_embeded_system_instructions` to control whether the plugin should append the embedded system instructions to the user provided ones before sending them to the AI model.

I dont know if this is a global setting or a command-level setting.

Help me to figure it out.


# GGL Clarifying the Scope of `append_embeded_system_instructions`

The `append_embeded_system_instructions` option is designed to be configurable at both a global level and a command-specific level. The command-specific setting, if provided, will override the global setting for that particular command.

Here's how it works based on the provided codebase:

1.  **Global Setting**:
    The option `append_embeded_system_instructions` is defined in `M.opts` within `lua/ai/init.lua` with a default value of `true`. This means that, by default, all AI commands will append the embedded system instructions. You can change this global default when setting up the plugin:
    ```lua
    require('ai').setup({
      append_embeded_system_instructions = false, -- Set to false to globally disable appending embedded instructions
    })
    ```

2.  **Command-Level Setting (Overrides Global)**:
    In `lua/ai/init.lua`, within the `M.handle` function, there's a check:
    ```lua
    local append_embeded = M.opts.append_embeded_system_instructions
    if def.append_embeded_system_instructions ~= nil then
      append_embeded = def.append_embeded_system_instructions
    end
    local instruction = aiconfig.getSystemInstructions(append_embeded)
    ```
    This logic explicitly checks if `def.append_embeded_system_instructions` is set for the current command (`def` refers to the prompt definition from `M.prompts`). If it is set (i.e., not `nil`), its value will take precedence over the global `M.opts.append_embeded_system_instructions`.

    This allows you to have a global default (e.g., `true`) but disable or enable it for specific commands. For example, if you want most commands to append embedded instructions but have one specific command that should *not*, you can define it like this in your `setup` call:

    ```lua
    require('ai').setup({
      -- Global setting (optional, default is true)
      append_embeded_system_instructions = true,

      prompts = {
        my_custom_prompt = {
          command = 'AICustomPrompt',
          loading_tpl = 'Thinking...',
          prompt_tpl = 'Analyze the following code: ${input}',
          result_tpl = 'Analysis: ${output}',
          require_input = true,
          -- Command-specific override: do NOT append embedded instructions for this command
          append_embeded_system_instructions = false,
        },
        another_prompt = {
          command = 'AIAnotherPrompt',
          loading_tpl = 'Working...',
          prompt_tpl = 'Summarize: ${input}',
          result_tpl = 'Summary: ${output}',
          require_input = true,
          -- This command will use the global setting (true in this example)
        },
      },
    })
    ```

In summary, the `append_embeded_system_instructions` option is already implemented to be flexible, allowing both a global default and specific overrides for individual AI commands.

**Files involved in this explanation:**
*   `lua/ai/init.lua`
*   `lua/ai/aiconfig.lua`

GoogleAI gemini-2.5-flash (17k in, 0k out)


