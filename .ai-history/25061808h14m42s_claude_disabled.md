# If the command used to run the plugin was "AIRedaction", then do not append the embeded system instructions.

The normal way to run this plugin is to take the user provided system instructions and append the embeded system instructions to it then send it to the AI model.

I would like to introduce an exception to this rule: if the command used to run the plugin was "AIRedaction", then do not append the embeded system instructions.

There are two ways to achieve that:

- implement a configuration option that can be set to true or false
- implement an exception harcoded in the plugin code 

The first option is cleaner and more flexible, but I have no idea about how bad is the second option.

Tell me which one is the best, and reword my query to make it more clear and concise.
Just reword the query, do not answer it.


# ANT Anthropic models are disabled

Anthropic disabled (0k in, 0k out)


