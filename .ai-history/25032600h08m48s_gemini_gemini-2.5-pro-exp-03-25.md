# Manage file inclusion and exclusion more efficiently. 

`aiconfig.listScannedFilesFromConfig()` handle the inclusion and exclusion of files based on a configuration file.

I find its way to handle it to be the worst on earth because when `exclude_patterns` happens to have something such as `node_modules` or `dist` in it,
execution is very slow.

First, do you agree with me?



# This is gemini-2.5-pro-exp-03-25 answer (11k in, 0k out)

Yes, I absolutely agree with you.

The current implementation of `aiconfig.listScannedFilesFromConfig()` is indeed inefficient, especially when dealing with large directories specified in `exclude_patterns` like `node_modules`, `dist`, `build`, `vendor`, etc.

Here's why:

1.  **Globbing Includes First:** The code first uses `vim.fn.glob()` to find *all* files matching the `include_patterns`. If an include pattern is broad (like `+**/*`), `glob` will traverse *every* directory, including `node_modules`, `dist`, etc., adding potentially thousands or millions of files to the `included_files` table.
2.  **Globbing Excludes Separately:** *After* potentially gathering a huge list of files, the code then uses `vim.fn.glob()` *again* for each `exclude_pattern`. This again traverses the directories specified in the exclude patterns (like `node_modules`).
3.  **Removal from Table:** Finally, it iterates through the results of the exclude globbing and removes entries from the `included_files` table.

**The core inefficiency is that `glob` is forced to traverse large, excluded directories potentially multiple times (once for includes if they match, and again explicitly for excludes), only to discard the results later.** This leads to significant slowdowns on projects with large dependency or build directories.

A much more efficient approach would be to avoid entering or processing excluded directories *during* the initial file discovery phase.
