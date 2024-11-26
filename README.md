# Acknowledgements

I would like first to thank [gera2ld](https://github.com/gera2ld) for his work on [ai.nvim](https://github.com/gera2ld/ai.nvim), because this plugin is a fork of his work. 
Without his plugin, there wouldnt be this one.
Thank you Gerald for your work.

# code-ai.nvim

A Neovim plugin powered by Google Gemini and ChatGPT.
Here is a demo:

![demo](./demo-code-ai.gif)


# How it works

- The plugin resides in Neovim.
- If the agents URLs are defined, it will send the prompt to the agent, which will send it to the corresponding LLM API.
  - It scans the files corresponding to the patterns defined in [.ai-scanned-files](./.ai-scanned-files) and builds a multi-turn chat from them.
  - It sends the [multi-turn chat and the prompt](./documentation/multi-turn-chat.json) to the agents
  - It receives the response from the agents and displays it in a popup
- If the agent URL are not defined, it will send the prompt directly to the corresponding LLM API.
  - It **does not scan** any files
  - It **does not build a multi-turn chat** but directly sends the prompt to the LLM API
  - It receives the response from the agents and displays it in a popup

# The agent

You can find the agent in the repository [code-ai-agent](https://github.com/rakotomandimby/code-ai-agent).

## Installation

First get API keys from [Google Cloud](https://ai.google.dev/gemini-api/docs/api-key) and [ChatGPT](https://platform.openai.com/api-keys) and set them in your environment:

For usage **WITHOUT** the agents, **don't set** the `gemini_agent_host` and `chatgpt_agent_host`.
For usage **WITH** the agents, **set** the `gemini_agent_host` and `chatgpt_agent_host`.

This is the configuration for the plugin:

```lua
{
  'rakotomandimby/code-ai.nvim',
  dependencies = 'nvim-lua/plenary.nvim',
  opts = {
    gemini_api_key = 'YOUR_GEMINI_API_KEY', -- or read from env: `os.getenv('GEMINI_API_KEY')`
    chatgtp_api_key = 'YOUR_CHATGPT_API_KEY', -- or read from env: `os.getenv('CHATGPT_API_KEY')`
    gemini_agent_host='http://172.16.76.1:5000', -- dont set if you dont want to use the agent
    chatgpt_agent_host='http://172.16.76.1:4000', -- dont set if you dont want to use the agent
    result_popup_gets_focus = true,
    -- Define custom prompts here, see below for more details
    locale = 'en',
    prompts = {
        javascript_vanilla = {
            command = 'AIJavascriptVanilla',
            instruction_tpl = 'Act as a Vanilla Javascript developer. Format you answer with Markdown.',
            prompt_tpl = '${input}',
            result_tpl = '${output}',
            loading_tpl = 'Loading...',
            require_input = true,
        },
        php_bare = {
            command = 'AIPhpBare',
            instruction_tpl = 'Act as a PHP developer. Format you answer with Markdown.',
            prompt_tpl = '${input}',
            result_tpl = '${output}',
            loading_tpl = 'Loading...',
            require_input = true,
        },
    },
  },
  event = 'VimEnter',
},
```

## Usage

If you ave configured the plugin following the instructions above, you can use the plugin by:
- Selecting a text in normal model
- Pressing `:` to enter the command mode
- Typing `AIJavascriptVanilla` or `AIPhpBare` and pressing `Enter`

# Several documentation

The prompts will be merged into built-in prompts. Here are the available fields for each prompt:

| Fields            | Required | Description                                                                                      |
| ---------------   | -------- | ------------------------------------------------------------------------------------------------ |
| `command`         | No       | A user command will be created for this prompt.                                                  |
| `instruction_tpl` | Yes      | Template for the instruction given to the model                                                  |                         
| `loading_tpl`     | No       | Template for content shown when communicating with Gemini. See below for available placeholders. |
| `prompt_tpl`      | Yes      | Template for the prompt string passed to Gemini. See below for available placeholders.           |
| `result_tpl`      | No       | Template for the result shown in the popup. See below for available placeholders.                |
| `require_input`   | No       | If set to `true`, the prompt will only be sent if text is selected or passed to the command.     |

Placeholders can be used in templates. If not available, it will be left as is.

| Placeholders          | Description                                                                                | Availability      |
| --------------------- | ------------------------------------------------------------------------------------------ | ----------------- |
| `${locale}`           | `opts.locale`                                                                              | Always            |
| `${input}`            | The text selected or passed to the command.                                                | Always            |
| `${output}`           | The result returned by Gemini.                                                             | After the request |


