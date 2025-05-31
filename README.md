# Acknowledgements

I would like first to thank [gera2ld](https://github.com/gera2ld) for his work on [ai.nvim](https://github.com/gera2ld/ai.nvim), because this plugin is a fork of his work. 
Without his plugin, there wouldnt be this one.
Thank you Gerald for your work.

# code-ai.nvim

A Neovim plugin powered by GoogleAI Gemini, OpenAI ChatGPT and Anthropic Claude to help you write code.

Here is a demo without using the agents:

[![Demonstration](https://img.youtube.com/vi/fkVt4ozc-w8/0.jpg)](https://www.youtube.com/watch?v=fkVt4ozc-w8)

Here is a demo using the agents:

[![Demonstration](https://img.youtube.com/vi/Mmv7dKrak7Q/0.jpg)](https://www.youtube.com/watch?v=Mmv7dKrak7Q)

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

First get API keys from 
- [Google Cloud](https://ai.google.dev/gemini-api/docs/api-key) 
- [ChatGPT](https://platform.openai.com/api-keys)
- [Anthropic](https://console.anthropic.com/settings/keys)

For usage **WITHOUT** the agents, **don't set** the `googleai_agent_host` nor `openai_agent_host` nor `anthropic_agent_host`.

For usage **WITH** the agents, **set** the `googleai_agent_host` and `openai_agent_host` and `anthropic_agent_host` to the URLs of the agents.

This is the configuration for the plugin:

```lua
{
    'rakotomandimby/code-ai.nvim',
    dependencies = 'nvim-lua/plenary.nvim',
    opts = {
        anthropic_model = 'claude-3-7-sonnet-latest',
        googeai_model   = 'gemini-2.0-flash-exp',
        openai_model    = 'gpt-4o-mini',

        anthropic_api_key = 'YOUR_ANTHROPIC_API_KEY',      -- or read from env: `os.getenv('ANTHROPIC_API_KEY')`
        googleai_api_key  = 'YOUR_GOOGLEAI_API_KEY',       -- or read from env: `os.getenv('GOOGLEAI_API_KEY')`
        openai_api_key    = 'YOUR_OPENAI_API_KEY',         -- or read from env: `os.getenv('OPENAI_API_KEY')`

        anthropic_agent_host = 'http://172.16.76.1:6000',    -- dont set if you dont want to use the agent
                                                             -- if you set, make sure the agents are running
        googleai_agent_host  = 'http://172.16.76.1:5000',    -- dont set if you dont want to use the agent
                                                             -- if you set, make sure the agents are running
        openai_agent_host    = 'http://172.16.76.1:4000',    -- dont set if you dont want to use the agent
                                                             -- if you set, make sure the agents are running
        result_popup_gets_focus = true,
        -- Define custom prompts here, see below for more details
        locale = 'en',
        prompts = {
            javascript_vanilla = {
                command = 'AIJavascriptVanilla',
                prompt_tpl = '${input}',
                result_tpl = '${output}',
                loading_tpl = 'Loading...',
                require_input = true,
                anthropic_model='claude-3-7-sonnet-latest',
                googleai_model='gemini-2.0-flash-exp',
                openai_model='gpt-4o-mini',
            },
            php_bare = {
                command = 'AIPhpBare',
                prompt_tpl = '${input}',
                result_tpl = '${output}',
                loading_tpl = 'Loading...',
                require_input = true,
                anthropic_model='claude-3-7-sonnet-latest',
                googleai_model='gemini-2.0-flash-exp',
                openai_model='gpt-4o-mini',
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

| Fields                 | Required | Description                                                                                      |
| ---------------------- | -------- | ------------------------------------------------------------------------------------------------ |
| `googleai_model`       | Yes      | The model to use for the GoogleAI Gemini API. Set it to 'disabled' if you don't want to use it.  |
| `openai_model`         | Yes      | The model to use for the OpenAI ChatGPT API. Set it to 'disabled' if you don't want to use it.   |
| `anthropic_model`      | Yes      | The model to use for the Anthropic Claude API. Set it to 'disabled' if you don't want to use it. |
| `googleai_api_key`     | Yes      | The API key for the GoogleAI Gemini API.                                                         |
| `openai_api_key`       | Yes      | The API key for the OpenAI ChatGPT API.                                                          |
| `anthropic_api_key`    | Yes      | The API key for the Anthropic Claude API.                                                        |
| `googleai_agent_host`  | No       | The host of the GoogleAI Gemini agent.                                                           |
| `openai_agent_host`    | No       | The host of the OpenAI ChatGPT agent.                                                            |
| `anthropic_agent_host` | No       | The host of the Anthropic Claude agent.                                                          |
| `command`              | Yes      | A user command will be created for this prompt.                                                  |
| `loading_tpl`          | No       | Template for content shown when communicating with Gemini. See below for available placeholders. |
| `prompt_tpl`           | Yes      | Template for the prompt string passed to Gemini. See below for available placeholders.           |
| `result_tpl`           | No       | Template for the result shown in the popup. See below for available placeholders.                |
| `require_input`        | No       | If set to `true`, the prompt will only be sent if text is selected or passed to the command.     |

Placeholders can be used in templates. If not available, it will be left as is.

| Placeholders          | Description                                                                                | Availability      |
| --------------------- | ------------------------------------------------------------------------------------------ | ----------------- |
| `${locale}`           | `opts.locale`                                                                              | Always            |
| `${input}`            | The text selected or passed to the command.                                                | Always            |
| `${output}`           | The result returned by the model.                                                          | After the request |


