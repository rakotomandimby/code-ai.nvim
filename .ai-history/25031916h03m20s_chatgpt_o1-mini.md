# Having system instruction in a `.ai-system-instructions.md` file.

Currently, system instructions are given in command definition.

I want to change that: I want to have a `.ai-system-instructions.md` file that contains all the system instructions.

The system instructions file will be located in the same directory as the `.ai-prompts.md` file.

We will have to remove givin the system instructions in the command definition.

Tell me the modifications I have to make to the code in order to implement this feature.




# This is o1-mini answer (8k in, 4k out)

To implement the feature where system instructions are loaded from a `.ai-system-instructions.md` file instead of being hardcoded in the command definitions, you'll need to make several modifications across your project files. Below are the detailed steps and code changes required to achieve this:

---

### **1. Create the `.ai-system-instructions.md` File**

First, ensure that a `.ai-system-instructions.md` file exists in your project. This file should be located in the same directory as the `.ai-prompts.md` file. Here's an example of how the content might look:

```markdown
# System Instructions

Act as a highly intelligent code assistant. Provide clear, concise, and accurate answers to user queries. Ensure all code snippets are properly formatted and tested.
```

*Feel free to tailor the system instructions to fit your specific needs.*

---

### **2. Update `lua/ai/aiconfig.lua`**

**a. Add a Function to Read System Instructions**

Modify `lua/ai/aiconfig.lua` to include a function that reads the `.ai-system-instructions.md` file. This function will fetch the system instructions from the specified file.

```lua
-- Add this function in lua/ai/aiconfig.lua

function aiconfig.getSystemInstructions()
  local system_instructions_path = aiconfig.getProjectRoot() .. '/.ai-system-instructions.md'
  local content = aiconfig.contentOf(system_instructions_path)
  
  if content == "" then
    common.log("Warning: System instructions file is missing or empty at " .. system_instructions_path)
  end
  
  return content
end
```

**b. Ensure `.ai-prompts.md` is Properly Managed**

If your project has functionality related to `.ai-prompts.md`, ensure that it doesn't conflict with the new system instructions. However, since your current requirement is only about system instructions, no changes are needed here unless `.ai-prompts.md` interacts with system instructions.

---

### **3. Modify `lua/ai/init.lua`**

**a. Remove Hardcoded `instruction_tpl` from `default_prompts`**

Since system instructions will now be loaded from an external file, remove the `instruction_tpl` from your `default_prompts`. This ensures that instructions are no longer hardcoded.

```lua
-- Modify the default_prompts table in lua/ai/init.lua

local default_prompts = {
  introduce = {
    command = 'AIIntroduceYourself',
    loading_tpl = 'Loading...',
    prompt_tpl = 'Say who you are, your version, and the currently used model',
    -- instruction_tpl = 'Act as a command line command that has been issued with the --help flag', -- Remove this line
    result_tpl = '${output}',
    require_input = false,
  }
}
```

**b. Integrate System Instructions into the `handle` Function**

Replace the usage of `instruction_tpl` with the system instructions fetched from the `.ai-system-instructions.md` file.

```lua
-- Locate the handle function in lua/ai/init.lua and modify it as follows

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

  -- Replace the following line:
  -- local instruction = M.fill(def.instruction_tpl, args)
  
  -- With this line to load instructions from the file:
  local instruction = aiconfig.getSystemInstructions()

  local prompt = M.fill(def.prompt_tpl, args)

  -- The rest of the function remains unchanged
  -- ...
end
```

**c. Handle Templating (Optional)**

If your `.ai-system-instructions.md` file contains placeholders similar to `${key}`, you can integrate templating. Modify the instruction assignment as follows:

```lua
-- Replace instruction assignment with templating
local system_instructions = aiconfig.getSystemInstructions()
local instruction = M.fill(system_instructions, args)
```

*Ensure that your `.ai-system-instructions.md` file uses the `${key}` syntax for placeholders if you opt for templating.*

---

### **4. Adjust Command Definitions**

Since the system instructions are no longer part of the command definitions, ensure that no residual references exist.

- **Remove Any Remaining `instruction_tpl` References:** Search your entire codebase for `instruction_tpl` and remove or comment them out if they exist elsewhere.

---

### **5. Update `lua/ai/common.lua` (Optional)**

To enhance logging and error handling related to system instructions, ensure that `lua/ai/common.lua` logs appropriate messages when system instructions are missing or empty.

```lua
-- Ensure this is already handled in aiconfig.getSystemInstructions()
-- If not, you can add additional logging here as needed
```

---

### **6. Verify `.ai-history` Directory Handling**

Your current history management does not directly interact with system instructions, but it's good practice to ensure that any changes do not inadvertently affect it. Review `lua/ai/history.lua` to confirm no dependencies on system instructions.

---

### **7. Test the Implementation**

After making the above changes, perform thorough testing to ensure:

- **System Instructions are Loaded Correctly:** Trigger a command that utilizes system instructions and verify that it reflects the content from `.ai-system-instructions.md`.
  
- **Fallbacks are Handled Gracefully:** If `.ai-system-instructions.md` is missing or empty, ensure that the application logs a warning and handles the situation without crashing.

- **No Residual Dependencies:** Ensure that all parts of the application function correctly without referencing the removed `instruction_tpl`.

---

### **8. Example Summary of Changes**

**`lua/ai/aiconfig.lua`**
```lua
-- Add this function at the end of lua/ai/aiconfig.lua

function aiconfig.getSystemInstructions()
  local system_instructions_path = aiconfig.getProjectRoot() .. '/.ai-system-instructions.md'
  local content = aiconfig.contentOf(system_instructions_path)
  
  if content == "" then
    common.log("Warning: System instructions file is missing or empty at " .. system_instructions_path)
  end
  
  return content
end

return aiconfig
```

**`lua/ai/init.lua`**
```lua
-- Remove 'instruction_tpl' from default_prompts
local default_prompts = {
  introduce = {
    command = 'AIIntroduceYourself',
    loading_tpl = 'Loading...',
    prompt_tpl = 'Say who you are, your version, and the currently used model',
    -- instruction_tpl = 'Act as a command line command that has been issued with the --help flag', -- Removed
    result_tpl = '${output}',
    require_input = false,
  }
}

-- Modify the handle function to use system instructions from the file
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

  -- Load system instructions from the .ai-system-instructions.md file
  local instruction = aiconfig.getSystemInstructions()
  -- If using templating:
  -- local system_instructions = aiconfig.getSystemInstructions()
  -- local instruction = M.fill(system_instructions, args)

  local prompt = M.fill(def.prompt_tpl, args)

  -- The rest of the function remains unchanged
  -- ...
end
```

---

### **9. Additional Recommendations**

- **Dynamic Reloading:** Consider adding functionality to reload system instructions without restarting the application. This can be done by adding an autocmd or a command that re-reads the `.ai-system-instructions.md` file.

- **Validation:** Implement validation to ensure that the system instructions meet certain criteria (e.g., non-empty, proper formatting) before using them.

- **Error Handling:** Enhance error handling to provide more informative messages to the user if the system instructions fail to load.

---

By following these steps, you'll successfully refactor your project to load system instructions from a `.ai-system-instructions.md` file, enhancing the flexibility and maintainability of your AI configurations.

