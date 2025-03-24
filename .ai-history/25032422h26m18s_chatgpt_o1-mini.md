# In `query.lua` files, if the model is the "disabled" string, don't query but just return "Model is disabled".

For each of the three `query.lua` files, I want that if the model name is the string "disabled", 
the `ask` and `askHeavy` functions must not perform real query to the model or the agent, 
but should return a JSON that will mwke the plugin to show a message like "Model is disabled".

Tell me the modifications to make to the three `query.lua` files to achieve this.



# This is o1-mini answer (9k in, 2k out)

To implement the desired functionality—preventing queries to AI models when the model name is set to `"disabled"` and returning a message like `"Model is disabled"`—you'll need to modify the `ask` and `askHeavy` functions in each of the three `query.lua` files: `anthropic/query.lua`, `chatgpt/query.lua`, and `gemini/query.lua`.

Below are detailed instructions and code snippets for each file to achieve this behavior.

---

### **General Approach**

1. **Check if the Model is Disabled:**
   - At the beginning of both the `ask` and `askHeavy` functions, verify if the `model` parameter is set to `"disabled"`.
   
2. **Return a Fake Response:**
   - If the model is disabled, construct a mock response that mimics the actual API response structure but contains a message indicating that the model is disabled.
   
3. **Invoke the Callback:**
   - Use `vim.schedule` to asynchronously call the `askCallback` function with the fake response, ensuring that the rest of the function does not execute.

---

### **1. `lua/ai/anthropic/query.lua`**

**Modifications Needed:**

Add checks at the beginning of both `ask` and `askHeavy` functions to handle the `"disabled"` model scenario.

**Updated Code Snippets:**

```lua
-- Inside lua/ai/anthropic/query.lua

-- Modify the askHeavy function
function query.askHeavy(model, instruction, prompt, opts, agent_host)
  if model == "disabled" then
    local fake_response = {
      status = 200,
      body = vim.fn.json_encode({
        usage = {
          input_tokens = 0,
          output_tokens = 0
        },
        content = {
          {
            text = "Model is disabled."
          }
        }
      })
    }
    vim.schedule(function()
      query.askCallback(fake_response, opts)
    end)
    return
  end

  -- Existing code follows...
  promptToSave = prompt
  modelUsed = model
  -- rest of the function
end

-- Modify the ask function
function query.ask(model, instruction, prompt, opts, api_key)
  if model == "disabled" then
    local fake_response = {
      status = 200,
      body = vim.fn.json_encode({
        usage = {
          input_tokens = 0,
          output_tokens = 0
        },
        content = {
          {
            text = "Model is disabled."
          }
        }
      })
    }
    vim.schedule(function()
      query.askCallback(fake_response, opts)
    end)
    return
  end

  -- Existing code follows...
  promptToSave = prompt
  modelUsed = model
  -- rest of the function
end
```

**Explanation:**

- **Check for Disabled Model:** The added `if model == "disabled"` blocks at the start of both functions intercept calls when the model is disabled.
  
- **Fake Response Construction:** A `fake_response` table mimics the structure expected by `formatResult`. Adjust the `usage` and `content` fields as needed to align with how `formatResult` processes the data.

- **Asynchronous Callback:** `vim.schedule` ensures that the callback is invoked asynchronously, maintaining the integrity of Neovim's event loop.

---

### **2. `lua/ai/chatgpt/query.lua`**

**Modifications Needed:**

Similarly, add checks in both `ask` and `askHeavy` functions.

**Updated Code Snippets:**

```lua
-- Inside lua/ai/chatgpt/query.lua

-- Modify the askHeavy function
function query.askHeavy(model, instruction, prompt, opts, agent_host)
  if model == "disabled" then
    local fake_response = {
      status = 200,
      body = vim.fn.json_encode({
        choices = {
          {
            message = {
              content = "Model is disabled."
            }
          }
        },
        usage = {
          prompt_tokens = 0,
          completion_tokens = 0
        }
      })
    }
    vim.schedule(function()
      query.askCallback(fake_response, opts)
    end)
    return
  end

  -- Existing code follows...
  promptToSave = prompt
  modelUsed = model
  -- rest of the function
end

-- Modify the ask function
function query.ask(model, instruction, prompt, opts, api_key)
  if model == "disabled" then
    local fake_response = {
      status = 200,
      body = vim.fn.json_encode({
        choices = {
          {
            message = {
              content = "Model is disabled."
            }
          }
        },
        usage = {
          prompt_tokens = 0,
          completion_tokens = 0
        }
      })
    }
    vim.schedule(function()
      query.askCallback(fake_response, opts)
    end)
    return
  end

  -- Existing code follows...
  promptToSave = prompt
  modelUsed = model
  -- rest of the function
end
```

**Explanation:**

- **Response Structure:** The `fake_response` here includes a `choices` array with a `message` field containing the disabled message, aligning with ChatGPT's API response format.

---

### **3. `lua/ai/gemini/query.lua`**

**Modifications Needed:**

Implement similar checks in both `ask` and `askHeavy` functions.

**Updated Code Snippets:**

```lua
-- Inside lua/ai/gemini/query.lua

-- Modify the askHeavy function
function query.askHeavy(model, instruction, prompt, opts, agent_host)
  if model == "disabled" then
    local fake_response = {
      status = 200,
      body = vim.fn.json_encode({
        candidates = {
          {
            content = nil,
            finishReason = "Model is disabled."
          }
        },
        usageMetadata = {
          promptTokenCount = 0,
          candidatesTokenCount = 0
        }
      })
    }
    vim.schedule(function()
      query.askCallback(fake_response, opts)
    end)
    return
  end

  -- Existing code follows...
  promptToSave = prompt
  modelUsed = model
  -- rest of the function
end

-- Modify the ask function
function query.ask(model, instruction, prompt, opts, api_key)
  if model == "disabled" then
    local fake_response = {
      status = 200,
      body = vim.fn.json_encode({
        candidates = {
          {
            content = nil,
            finishReason = "Model is disabled."
          }
        },
        usageMetadata = {
          promptTokenCount = 0,
          candidatesTokenCount = 0
        }
      })
    }
    vim.schedule(function()
      query.askCallback(fake_response, opts)
    end)
    return
  end

  -- Existing code follows...
  promptToSave = prompt
  modelUsed = model
  -- rest of the function
end
```

**Explanation:**

- **Response Structure:** For Gemini, the `fake_response` includes a `candidates` array with a `content` field set to `nil` and a `finishReason` indicating that the model is disabled. This aligns with the existing error handling in `formatResult`.

---

### **Additional Considerations**

1. **Consistent Logging:**
   - If desired, you can add logging statements within the `"disabled"` model checks to record when a disabled model is invoked.

   ```lua
   common.log("Model '" .. model .. "' is disabled. Skipping API query.")
   ```

2. **Handling Different Model States:**
   - Ensure that the `"disabled"` state is appropriately set in your configuration to prevent accidental disabling of models.

3. **Testing:**
   - After implementing these changes, thoroughly test each scenario:
     - Model enabled: Ensure normal functionality.
     - Model disabled: Ensure that the message `"Model is disabled."` is displayed without initiating any API calls.

4. **Error Handling:**
   - Confirm that other parts of the plugin gracefully handle the `"Model is disabled."` message without errors or unexpected behavior.

---

By following the above modifications for each `query.lua` file, your plugin will correctly handle scenarios where an AI model is disabled, providing clear feedback to the user without making unnecessary API calls.

