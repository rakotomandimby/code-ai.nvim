# Manage file exclusion more efficiently. 

`aiconfig.listScannedFilesFromConfig()` handle the inclusion and exclusion of files based on a configuration file.

I find its way to handle it to be the worst on earth because when `exclude_patterns` happens to have something such as `node_modules` or `dist` in it,
execution is very slow.

I want to change that, and first, I have put the `./lua/ai/globpattern.lua` to be an utility to handle the glob pattern.
Analyze the code of `./lua/ai/globpattern.lua` and laverage it to improve the performance of `aiconfig.listScannedFilesFromConfig()`.
I propose that we keep the current way to list files matching the `include_patterns` and then we filter out the files that match the `exclude_patterns` using the utility functions from `globpattern.lua`.

Propose a new implementation of `aiconfig.listScannedFilesFromConfig()` that uses the utility functions from `globpattern.lua` to handle the inclusion and exclusion of files more efficiently.



# This is o1-mini answer (0k in, 0k out)

ChatGPT API Error: Unsupported value: 'messages[0].role' does not support 'system' with this model.

