# What is the maximum size it can handle?

When handling large files, plenary gives this error:

```
Error executing callback:                                                                                                                                                                                                          
.../.local/share/nvim/lazy/plenary.nvim/lua/plenary/job.lua:406: Failed to spawn process
```

Looking at the documentation on Internet, I cannot find any information about the maximum size of files that plenary can handle.
Tell me the maximum size of files that plenary can handle, or how to find it out.


# GGL Okay, this is an excellent and common problem when dealing with external processes and large data.

The error `.../.local/share/nvim/lazy/plenary.nvim/lua/plenary/job.lua:406: Failed to spawn process` is quite telling. It means Plenary (or more accurately, the underlying `libuv` that Neovim uses for asynchronous operations, which Plenary leverages) is failing to even *start* the external command. This usually happens *before* the external command has a chance to complain about the data itself.

Plenary itself, as a Lua library, doesn't have a hardcoded limit on the size of Lua strings it can handle (which would be limited by available memory). The limitation you're hitting is almost certainly related to how data is passed to the child process (likely `curl` in your case, as `plenary.curl` is used extensively).

Here are the primary reasons this "Failed to spawn process" error occurs with large data, and how to investigate:

1.  **`ARG_MAX` - Maximum Command-Line Argument Length:**
    *   If any part of the data you're sending (even if it's not the entire file content, but perhaps a large instruction string or a JSON-encoded payload that becomes huge) is being passed as a command-line argument to the external process, you can hit this limit.
    *   Operating systems have a limit on the total length of command-line arguments plus environment variables.
    *   **How to check (Linux/macOS):** `getconf ARG_MAX` (This will give you the limit in bytes).
    *   **Relevance to your code:**
        *   In your `askLight` functions, the entire `instruction` and `prompt` are JSON-encoded into the `body`. If `instruction` (from `aiconfig.getSystemInstructions()`) or `prompt` (which can come from `M.getSelectedText()` or `aiconfig.contentOf()`) is massive, the resulting JSON string passed to `curl` (likely via its stdin, but the command itself might still be complex) could be an issue, though usually the body goes to stdin.
        *   The `askHeavy` functions send data in chunks, which is good. However, if a *single chunk* (e.g., the content of one file from `aiconfig.contentOf(context)`) is enormous, that single JSON-encoded message could be problematic.
        *   `common.uploadContent` passes the entire `content` (LLM response) as the body.

2.  **Pipe Buffer Limits / Stdin Handling:**
    *   `plenary.curl` (and `plenary.job` in general when sending a body) will typically send the request body to the `curl` command's standard input (stdin) via a pipe.
    *   While pipes are designed for streaming, there can be issues if the parent process (Neovim/Plenary) tries to write an enormous amount of data to the pipe *synchronously* during process setup, or if the OS pipe buffer fills up before the child process (`curl`) starts reading. This can lead to deadlocks or errors in spawning.
    *   The exact behavior here can be subtle and depend on `libuv`'s internals and OS specifics.

3.  **Memory Limits (Less Likely for "Failed to Spawn"):**
    *   If the system is extremely low on memory, it might fail to spawn new processes. This is less likely to be the direct cause of "Failed to spawn process" if it only happens with large data inputs, as the error usually occurs before the child process consumes significant memory. However, the parent process (Neovim) holding the large data in memory contributes to overall system memory pressure.

**How to Find Out the Limit (Empirically):**

Since it's not a fixed Plenary limit but an interaction with the OS and the external command, empirical testing is your best bet:

1.  **Isolate the Operation:** Create a minimal test case.
    *   Identify which specific `curl.post` or `curl.put` call is failing. Is it in `askLight`, `askHeavy` (and if so, for which file), or `common.uploadContent`?
    *   Write a small Lua script that *only* uses `plenary.curl` to send data of varying sizes, mimicking the failing call.

2.  **Minimal Test Script Example (mimicking `askLight` or `uploadContent`):**

    ```lua
    -- test_plenary_limit.lua
    local curl = require('plenary.curl')
    local fs = require('plenary.path')

    -- Create a large dummy file
    local function create_large_file(filepath, size_mb)
      local f = io.open(filepath, "w")
      if not f then
        print("Failed to open file for writing: " .. filepath)
        return
      end
      local chunk = string.rep("a", 1024) -- 1KB chunk
      for _ = 1, size_mb * 1024 do
        f:write(chunk)
      end
      f:close()
      print("Created file: " .. filepath .. " of size " .. size_mb .. "MB")
    end

    local test_file_path = "/tmp/large_test_data.txt"
    local target_url = "https://httpbin.org/post" -- A service that echoes POST data

    local function run_test(size_mb)
      print("Testing with " .. size_mb .. "MB...")
      create_large_file(test_file_path, size_mb)
      local content = fs:new(test_file_path):read()
      -- os.remove(test_file_path) -- Clean up immediately

      local body_to_send
      -- Mimic JSON structure if that's what you're sending
      -- For simplicity, let's just send raw content first
      -- If your actual body is JSON, then:
      -- body_to_send = vim.fn.json_encode({ data = content })
      body_to_send = content

      local job = curl.post(target_url, {
        body = body_to_send,
        callback = function(res)
          if res.exit_code == 0 and res.status >= 200 and res.status < 300 then
            print("SUCCESS for " .. size_mb .. "MB. Response status: " .. res.status)
            -- print("Response body (first 100 chars): " .. string.sub(res.body, 1, 100))
          else
            print("FAILURE for " .. size_mb .. "MB.")
            print("  Exit code: " .. tostring(res.exit_code))
            print("  Status: " .. tostring(res.status))
            print("  Stderr: " .. tostring(res.stderr))
            print("  Body: " .. tostring(res.body))
          end
        end
      })
      job:wait() -- Wait for the job to complete for synchronous testing
      print("Finished test for " .. size_mb .. "MB.")
    end

    -- Test with increasing sizes (binary search would be more efficient)
    -- Start small and increase
    run_test(1)  -- 1MB
    run_test(10) -- 10MB
    run_test(50) -- 50MB
    run_test(100) -- 100MB (likely to fail here or before if ARG_MAX or pipe issues)
    run_test(200)
    -- ... and so on, or use a loop and binary search for the failure point.
    ```
    You can run this from Neovim: `:luafile test_plenary_limit.lua`

3.  **Observe:**
    *   Note the size at which it starts failing with "Failed to spawn process."
    *   If it fails with a different error (e.g., `curl` itself times out or gives an error), then the spawning succeeded, but `curl` couldn't handle the data.

**Likely Culprits in Your Code:**

1.  **`aiconfig.contentOf(file_relative_path)`:** If any file listed in `.ai-scanned-files` is very large, this function will read its entire content into a Lua string.
    *   In `askHeavy`, this content is then put into a `body_chunk`. If `vim.json.encode(message)` for that chunk becomes excessively large, it could be the issue for that specific request in the sequence.
    *   In `askLight` (if you were to use `contentOf` to build the prompt, which you aren't directly but `getSelectedText` could be large), a similar issue.

2.  **`aiconfig.getSystemInstructions()`:** If `.ai-system-instructions.md` or `common-system-instructions.md` is extremely large.

3.  **`common.uploadContent()`:** The `result` from the LLM could be very large.

**Potential Solutions/Mitigations:**

1.  **Streaming (Harder with current `plenary.curl` for request bodies):**
    Ideally, for very large request bodies, `curl` would read from a stream or a file descriptor rather than having the entire body pre-loaded. `plenary.curl` might not directly support this mode of operation easily; it expects the `body` as a string.

2.  **Temporary Files (A common workaround for `curl`):**
    *   Write the large data to a temporary file.
    *   Use `curl`'s ability to read data from a file for the POST body (e.g., `curl -X POST --data-binary @/tmp/mydatafile <url>`).
    *   You would need to modify how `plenary.curl` is called, or potentially use `plenary.job` directly to construct this `curl` command. This adds complexity (temp file management).

3.  **Chunking (You're already doing this in `askHeavy` for the conversation):**
    *   Ensure that individual file contents passed to `askHeavy` are not themselves excessively large. You might need to add a size check in `aiconfig.listScannedFilesFromConfig` or before calling `aiconfig.contentOf` to warn or skip huge files.
    *   For `askLight`, if the prompt becomes too big, it's inherently problematic.
    *   For `common.uploadContent`, if the LLM response is huge, you're in a similar boat.

4.  **Configuration/User Awareness:**
    *   Warn users if they try to include extremely large files in `.ai-scanned-files`.
    *   Potentially set a configurable maximum size for files to be processed by `aiconfig.contentOf`.

**Recommendation:**

Start with the empirical testing using the minimal script. This will give you a practical upper bound for your specific OS and Neovim/Plenary setup.
Once you find the approximate limit, review your code to see where such large data blobs might originate:
*   Is it one massive file in `.ai-scanned-files`?
*   Is it a huge system instruction file?
*   Is it a very large selection passed as input?
*   Is it a very large response from the LLM being uploaded?

The "Failed to spawn process" error strongly points to the OS refusing to start the `curl` command because the arguments/environment/initial stdin pipe setup is too large, with `ARG_MAX` or issues with how `libuv` passes large initial stdin data being the most probable causes.

GoogleAI gemini-2.5-pro-preview-05-06 (17k in, 2k out)


