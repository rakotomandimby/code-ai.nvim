# Code review 

REview the code and tell me what you think


# OPN Overall impressions  
-------------------

The structure is clear and the three provider adapters (Anthropic, GoogleAI, OpenAI) share the same surface API, which makes the orchestration code in `init.lua` easy to follow. The popup plumbing and command registration are tidy, and the upload/history hooks are neatly centralized in `common.lua`.

That said, there are a couple of **severe functional bugs** plus a handful of race conditions and edge cases you probably want to address sooner rather than later. Below are the most important points I noticed while reading through the code.

---</br>---

Major issues (need attention)  
-----------------------------

1. **OpenAI `formatResult` assumes a non‑existent response shape**  
   ```lua
   local result = data.output[2].content[1].text …
   ```  
   The v1 Chat Completions API (and the `disabled_response` you build) return `choices[1].message.content`. Accessing `data.output` will throw a Lua error the first time a real request succeeds (or even when the model is “disabled”). This needs to be fixed to match the actual schema returned by the endpoint you call in `askLight`.

2. **Per-request state races (`promptToSave`, `modelUsed`)**  
   Each provider module stores the current prompt/model in module-level variables. If the user triggers a second command before the first response comes back, the globals are overwritten and the first callback will log/upload/history the *wrong* prompt/model. Please thread this state through the async path (e.g., include it in `opts`, or capture it in a closure) instead of relying on globals.

3. **Uploads still run when models are “disabled”**  
   `common.uploadContent` only skips when `model_name == 'disabled'`, but the callers pass strings like `"Anthropic (disabled)"`, so the check never fires and you still attempt to PUT to the remote endpoint. Either pass the raw model or change the guard to detect `string.find(model_name, 'disabled', 1, true)` or similar.

4. **UI width/height safety**  
   `M.createPopup` subtracts fixed margins (`width - 8`, `height - 4`). On narrow splits this can become ≤0 and trigger a runtime error when opening the floating window. Clamp to a sensible minimum.

5. **`common.askCallback` assumes a successful JSON payload**  
   When `curl` returns an outright network failure, `res.status` (or `res.body`) may be `nil`. Right now that would raise. A guard with an informative error message would make debugging much easier.

6. **Command setup forces three providers**  
   `setup` errors unless *all* three models and API keys are provided. Given the effort spent on the `"disabled"` pathway, it would be nice if setting one or two providers to “disabled” (or leaving them blank) kept everything working. Right now users who only have one provider can’t use the plugin.

---</br>---

Medium priorities / maintainability  
------------------------------------

* `common.askCallback` overwrites `result` with the return value of `handleResult`. Because `handleResult` currently returns `nil`, `opts.callback` receives `nil`. That’s harmless for the current “no-op” callbacks, but confusing. Consider not reassigning or guarding the callback with `if opts.callback then … end`.

* The token display uses `math.floor(prompt_tokens / 1000)` which means anything below 1k renders as `0k`. A simple `string.format("%.1fk")` or an adaptive formatter would be clearer.

* `common.insertWordToTitle`’s `gsub('^# ', …)` only matches a single `#`. If your results start with `##` or deeper headings, the tag never gets inserted.

* `M.hasLetters` filters out prompts that contain only digits/punctuation. Depending on the usage, that may be too strict (think hex values, regexes, etc.).

* `args.output = (args.anthropic_output or '') .. …` concatenates without newline separators, so the three provider responses run together. Add an extra `\n\n` between them when all three are present.

* `common.uploadContent` assumes the callback always receives a response. If `curl.put` fails at the transport level, `res` may be `nil`. It would be worth adding a `res and res.status` guard.

* The duplication between the three query modules is starting to make maintenance harder. Consider factoring out the shared parts (state management, disabled path, upload bookkeeping) into helper functions.

---</br>---

Smaller nits / nice-to-haves  
----------------------------

* `splitLines`/`joinLines` can likely be replaced with `vim.split` / `table.concat` unless you specifically need the current behaviour.

* Logging to `/tmp/aiconfig.log` with `io.open` is fine, but you might want to make the path configurable or at least add error handling for non-Unix systems.

* `history.saveToHistory` calls `vim.split(content, '\n')` without `{plain = true}`; that’s safe for `\n` but you might adopt the same option you use elsewhere for consistency.

* The `askHeavy` implementations leak HTTP requests if the intermediate chunk fails (the chain is not stopped). Maybe acceptable for now, just something to keep in mind.

---</br>---

Bottom line  
-----------

The overall design is clean and extensible, but the OpenAI result parsing bug and the shared mutable state are significant enough to cause crashes or incorrect history/uploads in everyday use. I’d address those first, then tighten up the error handling and make the “disabled”/single-provider flow a first-class citizen. After that, most remaining issues are polish and maintainability improvements.

OpenAI gpt-5-codex (0k in, 0k out)


