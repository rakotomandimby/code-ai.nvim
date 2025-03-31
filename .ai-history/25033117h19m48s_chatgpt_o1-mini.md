# Handle Errors

When the Anthropic API answers with other than an HTTP 200 status code, the response has this structure:

```json
{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
```

When the ChatGPT API answers with other than an HTTP 200 status code, the response has this structure:

```json
{"error":
  {
    "message":"This model's maximum context length is 128000 tokens.",
    "type":"invalid_request_error",
    "param":"messages",
    "code":"context_length_exceeded"
  }
}
```

When the Gemini API answers with other than an HTTP 200 status code, the response has this structure:

```json
{
  "error": {
    "code": 400,
    "message": "The request is missing a required parameter, includes an invalid parameter value, includes a parameter more than once, or is otherwise malformed.",
    "status": "BAD_REQUEST"
  }
}
```

I want to gracefully handle specific API errors from Anthropic, ChatGPT, and Gemini in respective `query.ask()` methods. 
We do not touch the `query.askHeavy()`.

I want the `query.ask()` method of each API to handle, extract the error message, and display it. 

Tell me the modifications to make to the code in order to achieve that.





# This is o1-mini answer (11k in, 5k out)

To gracefully handle specific API errors from Anthropic, ChatGPT, and Gemini in their respective `query.ask()` methods, you need to modify each `ask()` function to include a custom `handleError` function. This function will parse the error response from the API, extract the relevant error message, and display it to the user. Below are the detailed steps and code modifications for each API:

---

### **1. Anthropic (`lua/ai/anthropic/query.lua`)**

**Objective:** Handle Anthropic API errors by extracting the `error.message` from the response and displaying it.

**Modifications:**

1. **Define a Custom `handleError` Function:**  
   Add a `handleError` function within the `ask()` method that parses the error response and extracts the error message.

2. **Assign `handleError` to `opts`:**  
   Ensure that this function is assigned to the `opts` table, so it gets invoked by `common.askCallback` when an error occurs.

**Updated `query.ask()` Function:**

```lua
-- Inside lua/ai/anthropic/query.lua

function query.ask(model, instruction, prompt, opts, api_key)
  promptToSave = prompt
  modelUsed = model

  -- Define handleError function for Anthropic API
  opts.handleError = function(status, body)
    local data = vim.fn.json_decode(body)
    if data and data.error and data.error.message then
      return "Anthropic API Error: " .. data.error.message
    else
      return "Anthropic API returned status " .. tostring(status) .. " with an unknown error."
    end
  end

  if model == "disabled" then
    vim.schedule(function() 
      query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, opts) 
    end)
    return
  end

  local api_host = 'https://api.anthropic.com'
  local path = '/v1/messages'
  
  curl.post(api_host .. path, {
    headers = {
      ['Content-type'] = 'application/json',
      ['x-api-key'] = api_key,
      ['anthropic-version'] = '2023-06-01'
    },
    body = vim.fn.json_encode({
      model = model,
      max_tokens = 8192,
      system = instruction,
      messages = {
        { role = 'user', content = prompt }
      }
    }),
    callback = function(res)
      common.log("Before Anthropic callback call")
      vim.schedule(function() query.askCallback(res, opts) end)
    end
  })
end
```

---

### **2. ChatGPT (`lua/ai/chatgpt/query.lua`)**

**Objective:** Handle ChatGPT API errors by extracting the `error.message` from the response and displaying it.

**Modifications:**

1. **Define a Custom `handleError` Function:**  
   Add a `handleError` function within the `ask()` method that parses the error response and extracts the error message.

2. **Assign `handleError` to `opts`:**  
   Ensure that this function is assigned to the `opts` table, so it gets invoked by `common.askCallback` when an error occurs.

**Updated `query.ask()` Function:**

```lua
-- Inside lua/ai/chatgpt/query.lua

function query.ask(model, instruction, prompt, opts, api_key)
  promptToSave = prompt
  modelUsed = model

  -- Define handleError function for ChatGPT API
  opts.handleError = function(status, body)
    local data = vim.fn.json_decode(body)
    if data and data.error and data.error.message then
      return "ChatGPT API Error: " .. data.error.message
    else
      return "ChatGPT API returned status " .. tostring(status) .. " with an unknown error."
    end
  end

  if model == "disabled" then
    vim.schedule(function() 
      query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, opts) 
    end)
    return
  end

  local api_host = 'https://api.openai.com'
  local path = '/v1/chat/completions'
  
  curl.post(api_host .. path, {
    headers = {
      ['Content-type'] = 'application/json',
      ['Authorization'] = 'Bearer ' .. api_key
    },
    body = vim.fn.json_encode({
      model = model,
      messages = string.sub(model, 1, 2) == 'o1' and
        { { role = 'user', content = instruction .. '\n' .. prompt } } or
        { 
          { role = 'system', content = instruction },
          { role = 'user', content = prompt }
        }
    }),
    callback = function(res)
      common.log("Before ChatGPT callback call")
      vim.schedule(function() query.askCallback(res, opts) end)
    end
  })
end
```

---

### **3. Gemini (`lua/ai/gemini/query.lua`)**

**Objective:** Handle Gemini API errors by extracting the `error.message` from the response and displaying it.

**Modifications:**

1. **Define a Custom `handleError` Function:**  
   Add a `handleError` function within the `ask()` method that parses the error response and extracts the error message.

2. **Assign `handleError` to `opts`:**  
   Ensure that this function is assigned to the `opts` table, so it gets invoked by `common.askCallback` when an error occurs.

**Updated `query.ask()` Function:**

```lua
-- Inside lua/ai/gemini/query.lua

function query.ask(model, instruction, prompt, opts, api_key)
  promptToSave = prompt
  modelUsed = model

  -- Define handleError function for Gemini API
  opts.handleError = function(status, body)
    local data = vim.fn.json_decode(body)
    if data and data.error and data.error.message then
      return "Gemini API Error: " .. data.error.message
    else
      return "Gemini API returned status " .. tostring(status) .. " with an unknown error."
    end
  end

  if model == "disabled" then
    vim.schedule(function() 
      query.askCallback({ status = 200, body = vim.json.encode(disabled_response) }, opts) 
    end)
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
      system_instruction = { parts = { text = instruction } },
      contents = { { role = 'user', parts = { { text = prompt } } } },
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
      common.log("Before Gemini callback call")
      vim.schedule(function() query.askCallback(res, opts) end)
    end
  })
end
```

---

### **Explanation of Modifications**

1. **Custom `handleError` Function:**
   - **Purpose:** Parses the error response from the API and extracts a user-friendly error message.
   - **Implementation:** The function uses `vim.fn.json_decode` to parse the JSON response and then navigates to the specific fields containing the error message based on the API structure.

2. **Assigning `handleError` to `opts`:**
   - By assigning the `handleError` function to the `opts` table, you leverage the existing `common.askCallback` mechanism to handle errors uniformly across different APIs.
   - When an error occurs (i.e., `res.status ~= 200`), `common.askCallback` checks if `opts.handleError` is defined and invokes it to get the formatted error message.

3. **Maintaining Existing Functionality:**
   - The rest of the `ask()` method remains unchanged, ensuring that successful responses continue to be processed and displayed as intended.
   - The `askHeavy()` methods are left untouched, as per your instructions.

---

### **Testing the Modifications**

After implementing the above changes, it's essential to test each API integration to ensure that:

- **Successful Requests:**  
  No changes should occur; the APIs should continue to function as before, displaying results in the popup.

- **Error Cases:**  
  Simulate API errors (e.g., by providing invalid credentials or exceeding rate limits) and verify that the custom error messages are correctly extracted and displayed to the user.

**Example Test Cases:**

1. **Anthropic API Overloaded Error:**
   - **Trigger:** Simulate an overloaded state.
   - **Expected Output:**  
     `"Anthropic API Error: Overloaded"`

2. **ChatGPT Context Length Exceeded:**
   - **Trigger:** Send a prompt that exceeds the context length.
   - **Expected Output:**  
     `"ChatGPT API Error: This model's maximum context length is 128000 tokens."`

3. **Gemini Bad Request Error:**
   - **Trigger:** Send a malformed request.
   - **Expected Output:**  
     `"Gemini API Error: The request is missing a required parameter, includes an invalid parameter value, includes a parameter more than once, or is otherwise malformed."`

---

### **Final Notes**

- **Logging:**  
  The `common.log` function continues to log all activities, including when errors are encountered. This is useful for debugging purposes.

- **Extensibility:**  
  If additional APIs are integrated in the future, you can follow the same pattern to handle their specific error structures.

- **Error Handling in `common.lua`:**  
  Ensure that the `common.askCallback` function correctly utilizes the `handleError` from `opts`. The modifications above presume that this function remains unchanged and correctly invokes `handleError` when provided.

By following the above modifications, your project will now gracefully handle and display specific error messages from Anthropic, ChatGPT, and Gemini APIs, enhancing the user experience and making debugging easier.

