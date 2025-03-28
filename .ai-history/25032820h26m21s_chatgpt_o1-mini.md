# Manage file exclusion more efficiently. 

`aiconfig.listScannedFilesFromConfig()` handle the inclusion and exclusion of files based on a configuration file.

I find its way to handle it to be the worst on earth because when `exclude_patterns` happens to have something such as `node_modules` or `dist` in it,
execution is very slow.

I want to change that, and first, I have put the `./lua/ai/globpattern.lua` to be an utility to handle the glob pattern.
Analyze the code of `./lua/ai/globpattern.lua` and laverage it to improve the performance of `aiconfig.listScannedFilesFromConfig()`.
I propose that we check the matching of the filepath against the `exclude_patterns` before pushing it to the `included_files` list.
We should be able to get rid of the `excluded_files` list, because we already avoided pushing the excluded files to the `included_files` list.

Propose a new implementation of `aiconfig.listScannedFilesFromConfig()` that uses the utility functions from `globpattern.lua` to handle the inclusion and exclusion of files more efficiently.



# This is o1-mini answer (10k in, 4k out)

Certainly! Let's address the performance issues in `aiconfig.listScannedFilesFromConfig()` by leveraging the `globpattern.lua` utility you've created. The primary goal is to efficiently handle file inclusion and exclusion, especially when dealing with large directories like `node_modules` or `dist`.

## Overview of the Proposed Solution

1. **Pattern Compilation**:
   - Convert all glob patterns (both inclusion and exclusion) into Lua patterns using the `globpattern.globtopattern` function. This precompilation step ensures faster pattern matching during file traversal.

2. **Efficient File Traversal**:
   - Instead of using `vim.fn.glob` multiple times (which can be slow for large directories), we'll perform a single recursive traversal of the project root directory.
   - During traversal, for each file encountered:
     - **Exclude First**: Check if the file path matches any of the exclusion patterns. If it does, skip processing this file or directory.
     - **Include Next**: If the file isn't excluded, check if it matches any of the inclusion patterns. If it does, add it to the `included_files` list.

3. **Optimized Data Handling**:
   - By avoiding the separate collection and subsequent removal of excluded files, we reduce the number of operations and improve overall performance.
   - Utilize a table (`included_files`) with file paths as keys to prevent duplicates efficiently.

4. **Sorting and Finalization**:
   - After collecting all relevant files, sort them by size in descending order to prioritize larger files if needed.
   - Extract the sorted file paths into a final list for use.

## Implementation Details

Below is the revised implementation of the `listScannedFilesFromConfig` function within your `lua/ai/aiconfig.lua` file. This version incorporates the `globpattern.lua` utility for efficient pattern matching and optimizes the traversal process to handle exclusions upfront.

```lua
-- lua/ai/aiconfig.lua

local aiconfig = {}
local common = require('ai.common')
local globpattern = require('ai.globpattern')
local vim_loop = vim.loop

-- Existing functions (findSystemInstructionsFile, getSystemInstructions, etc.) remain unchanged

-- Helper function to recursively traverse directories
local function traverse(dir, callback)
  local scandir = vim_loop.fs_scandir(dir)
  if not scandir then return end

  while true do
    local name, type = vim_loop.fs_scandir_next(scandir)
    if not name then break end
    local path = dir .. '/' .. name
    callback(path, type)
    if type == 'directory' then
      traverse(path, callback) -- Recursive call for subdirectories
    end
  end
end

function aiconfig.listScannedFilesFromConfig()
  local config = aiconfig.findScannedFilesConfig()
  if config == "" then
    return {}
  end

  local include_patterns = {}
  local exclude_patterns = {}

  -- Read the config file and separate include and exclude patterns
  for line in io.lines(config) do
    local trimmed_line = vim.trim(line)
    if vim.startswith(trimmed_line, "+") then
      local pattern = trimmed_line:sub(2)
      table.insert(include_patterns, globpattern.globtopattern(pattern))
    elseif vim.startswith(trimmed_line, "-") then
      local pattern = trimmed_line:sub(2)
      table.insert(exclude_patterns, globpattern.globtopattern(pattern))
    end
  end

  -- Function to check if a path matches any pattern in a list
  local function matches_any(path, patterns)
    for _, pattern in ipairs(patterns) do
      if path:match(pattern) then
        return true
      end
    end
    return false
  end

  local included_files = {}

  local project_root = aiconfig.getProjectRoot()
  
  traverse(project_root, function(path, type)
    -- Get the relative path from project root
    local relative_path = path:gsub("^" .. project_root .. "/?", "")

    if type == 'file' then
      -- Check exclusion patterns first
      if not matches_any(relative_path, exclude_patterns) then
        -- Check inclusion patterns
        if matches_any(relative_path, include_patterns) then
          included_files[path] = true
        end
      end
    elseif type == 'directory' then
      -- If directory matches any exclusion pattern, skip traversing it
      if matches_any(relative_path, exclude_patterns) then
        -- Return false to indicate that traversal should skip this directory
        -- However, since our traverse function doesn't support skipping,
        -- we need to handle it manually. Modify the traverse function accordingly.
        -- For now, directories are always traversed; to optimize, consider enhancing
        -- the traverse function to accept a skip flag.
        -- Alternatively, implement the skip logic here if needed.
      end
    end
  end)

  -- Convert the included_files table to a list and gather their sizes
  local files_with_sizes = {}
  for file, _ in pairs(included_files) do
    local file_info = vim_loop.fs_stat(file)
    if file_info and file_info.type == 'file' then
      table.insert(files_with_sizes, {
        path = file,
        size = file_info.size
      })
    end
  end

  -- Sort by file size (bigger to smaller)
  table.sort(files_with_sizes, function(a, b)
    return a.size > b.size
  end)

  -- Extract just the file paths from the sorted list
  local final_files = {}
  for _, file_data in ipairs(files_with_sizes) do
    table.insert(final_files, file_data.path)
  end

  return final_files
end

-- Rest of aiconfig.lua remains unchanged

return aiconfig
```

### Explanation of the Changes

1. **Pattern Compilation**:
   - After separating inclusion (`include_patterns`) and exclusion (`exclude_patterns`) from the config file, each glob pattern is converted to a Lua pattern using `globpattern.globtopattern(pattern)`.
   - This precompilation allows faster and more efficient matching during traversal.

2. **File Traversal Optimization**:
   - Introduced a helper function `traverse` that recursively traverses directories using `vim.loop.fs_scandir`.
   - For each file encountered:
     - **Exclusion Check**: The file's relative path is checked against all exclusion patterns first using the `matches_any` function. If it matches any exclusion pattern, the file is skipped and not considered for inclusion.
     - **Inclusion Check**: If the file isn't excluded, it is then checked against the inclusion patterns. If it matches any inclusion pattern, it's added to the `included_files` table.
   - **Note**: The current `traverse` function does not support skipping entire directories based on exclusion patterns. To fully optimize, you might consider enhancing the `traverse` function to allow early exits for directories that match exclusion patterns. However, this would require more complex handling, such as modifying the traversal logic to respect skip flags.

3. **Efficiency Gains**:
   - By handling exclusion before inclusion, we prevent unnecessary processing of files that don't meet the criteria, thus improving performance especially in large directories.
   - Using Lua tables with file paths as keys (`included_files[path] = true`) ensures that each file is only processed once, avoiding duplicates without additional overhead.

4. **Additional Considerations**:
   - **Relative Paths**: Matching patterns are performed against relative paths from the project root. This ensures that patterns like `node_modules/**` correctly identify files within the `node_modules` directory.
   - **Directory Exclusions**: While the current implementation does not skip entire directories based on exclusion patterns, you can enhance the `traverse` function to support this feature for even greater performance improvements.

## Enhancing Directory Skipping (Optional)

To further optimize the traversal by skipping entire directories that match exclusion patterns (e.g., `node_modules`), you can modify the `traverse` function to include a skip condition. Here's how you can achieve that:

```lua
-- Helper function to recursively traverse directories with skip support
local function traverse(dir, callback, exclude_dir_patterns)
  local scandir = vim_loop.fs_scandir(dir)
  if not scandir then return end

  while true do
    local name, type = vim_loop.fs_scandir_next(scandir)
    if not name then break end
    local path = dir .. '/' .. name
    local relative_path = path:gsub("^" .. aiconfig.getProjectRoot() .. "/?", "")
    
    if type == 'directory' then
      -- Check if the directory matches any exclusion pattern
      if not matches_any(relative_path, exclude_dir_patterns) then
        traverse(path, callback, exclude_dir_patterns) -- Recursive call for subdirectories
      else
        common.log("Skipping excluded directory: " .. relative_path)
      end
    elseif type == 'file' then
      callback(path, type)
    end
  end
end

function aiconfig.listScannedFilesFromConfig()
  local config = aiconfig.findScannedFilesConfig()
  if config == "" then
    return {}
  end

  local include_patterns = {}
  local exclude_patterns = {}

  -- Read the config file and separate include and exclude patterns
  for line in io.lines(config) do
    local trimmed_line = vim.trim(line)
    if vim.startswith(trimmed_line, "+") then
      local pattern = trimmed_line:sub(2)
      table.insert(include_patterns, globpattern.globtopattern(pattern))
    elseif vim.startswith(trimmed_line, "-") then
      local pattern = trimmed_line:sub(2)
      table.insert(exclude_patterns, globpattern.globtopattern(pattern))
    end
  end

  -- Function to check if a path matches any pattern in a list
  local function matches_any(path, patterns)
    for _, pattern in ipairs(patterns) do
      if path:match(pattern) then
        return true
      end
    end
    return false
  end

  local included_files = {}

  local project_root = aiconfig.getProjectRoot()
  
  traverse(project_root, function(path, type)
    -- Get the relative path from project root
    local relative_path = path:gsub("^" .. project_root .. "/?", "")

    -- Check exclusion patterns
    if not matches_any(relative_path, exclude_patterns) then
      -- Check inclusion patterns
      if matches_any(relative_path, include_patterns) then
        included_files[path] = true
      end
    end
  end, exclude_patterns)

  -- Convert the included_files table to a list and gather their sizes
  local files_with_sizes = {}
  for file, _ in pairs(included_files) do
    local file_info = vim_loop.fs_stat(file)
    if file_info and file_info.type == 'file' then
      table.insert(files_with_sizes, {
        path = file,
        size = file_info.size
      })
    end
  end

  -- Sort by file size (bigger to smaller)
  table.sort(files_with_sizes, function(a, b)
    return a.size > b.size
  end)

  -- Extract just the file paths from the sorted list
  local final_files = {}
  for _, file_data in ipairs(files_with_sizes) do
    table.insert(final_files, file_data.path)
  end

  return final_files
end
```

### Explanation of Enhancements

1. **Directory Skipping**:
   - The modified `traverse` function now accepts an additional parameter `exclude_dir_patterns`, which contains patterns that, if matched by a directory's relative path, will cause the traversal to skip entering that directory.
   - This effectively prevents the traversal from descending into excluded directories like `node_modules` or `dist`, significantly reducing the number of files processed.

2. **Logging Skipped Directories**:
   - Added a log statement to record which directories are being skipped. This can be helpful for debugging and ensuring that exclusion patterns are working as intended.

3. **Callback Optimization**:
   - The callback function is only called for files, not directories, since directories are either traversed or skipped based on exclusion patterns.

## Final Notes

- **Performance**: By handling exclusions upfront and avoiding unnecessary traversal into large directories, this implementation should provide a noticeable improvement in performance.
  
- **Flexibility**: This approach maintains flexibility in specifying both inclusion and exclusion patterns, allowing for precise control over which files are scanned.

- **Error Handling**: Ensure that appropriate error handling is in place, especially when dealing with filesystem operations, to handle cases like permission issues or non-existent directories gracefully.

- **Testing**: After implementing the changes, thoroughly test with various configurations to ensure that inclusion and exclusion patterns behave as expected and that performance improvements are realized.

By integrating the `globpattern.lua` utility and optimizing the traversal logic, your `listScannedFilesFromConfig` function should now handle large directories more efficiently, providing a smoother experience.

