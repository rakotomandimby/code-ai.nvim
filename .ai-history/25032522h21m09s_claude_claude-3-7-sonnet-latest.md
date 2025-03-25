# Sort files by size, bigger to smaller

`aiconfig.listScannedFilesFromConfig()` returns a list of files are scanned and orders it by full path.

I want to change that and order it by file size, from bigger to smaller.

Tell me the changes to make to the code in order to achieve that.






# This is claude-3-7-sonnet-latest answer (11k in, 2k out)

# Sorting Files by Size (Bigger to Smaller)

To modify the `aiconfig.listScannedFilesFromConfig()` function to sort files by size from bigger to smaller, we need to update the code in `lua/ai/aiconfig.lua`. Here's the implementation:

```lua
local aiconfig = {}

function aiconfig.findSystemInstructionsFile()
  local path = vim.fn.getcwd() .. '/.ai-system-instructions.md'
  local file = io.open(path, "r")
  if file ~= nil then
    io.close(file)
    return path
  else
    return ""
  end
end

function aiconfig.getSystemInstructions()
  local path = aiconfig.findSystemInstructionsFile()
  if path == "" then
    return ""
  end

  local file = io.open(path, "r")
  if not file then
    return ""
  end

  local content = file:read("*all")
  file:close()
  return content
end

function aiconfig.findScannedFilesConfig()
  local path = vim.fn.getcwd() .. '/.ai-scanned-files'
  local file = io.open(path, "r")
  if file ~= nil then
    io.close(file)
    return path
  else
    return ""
  end
end

function aiconfig.getProjectRoot()
  -- To find the project root, we look upward for several files or directory, in this order:
  -- 1. The .ai-scanned-files file
  -- 2. The .git directory
  -- 3. The .gitignore file
  -- 4. The README.md file

  local project_root = vim.fn.getcwd() -- Start with the current working directory
  -- Check if the .ai-scanned-files file exists here or in any parent directory
  local configFile = aiconfig.findScannedFilesConfig()
  if configFile ~= "" then
    project_root = vim.fn.fnamemodify(configFile, ":h") -- Get the parent directory of the .ai-scanned-files file
    return project_root
  end

  -- Check if the .git directory exists here or in any parent directory
  local gitDir = vim.fn.finddir(".git", ".;") -- Find the .git directory
  if gitDir ~= "" then
    project_root = vim.fn.fnamemodify(gitDir, ":h") -- Get the parent directory of the .git directory
    return project_root
  end

  -- Check if the .gitignore file exists here or in any parent directory
  local gitignoreFile = vim.fn.findfile(".gitignore", ".;") -- Find the .gitignore file
  if gitignoreFile ~= "" then
    project_root = vim.fn.fnamemodify(gitignoreFile, ":h") -- Get the parent directory of the .gitignore file
    return project_root
  end

  -- Check if the README.md file exists here or in any parent directory
  local readmeFile = vim.fn.findfile("README.md", ".;") -- Find the README.md file
  if readmeFile ~= "" then
    project_root = vim.fn.fnamemodify(readmeFile, ":h") -- Get the parent directory of the README.md file
    return project_root
  end
  return project_root
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
      table.insert(include_patterns, trimmed_line:sub(2)) -- Remove the '+' and add to include patterns
    elseif vim.startswith(trimmed_line, "-") then
      table.insert(exclude_patterns, trimmed_line:sub(2)) -- Remove the '-' and add to exclude patterns
    end
  end

  -- Step 1: Gather all files that match the include patterns
  local included_files = {}
  for _, pattern in ipairs(include_patterns) do
    for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
      included_files[file] = true -- Use a table to avoid duplicates
    end
  end

  -- Step 2: Remove files that match the exclude patterns
  for _, pattern in ipairs(exclude_patterns) do
    for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
      included_files[file] = nil -- Remove excluded files
    end
  end

  -- Step 3: Create a list of files with their sizes
  local files_with_sizes = {}
  for file, _ in pairs(included_files) do
    local file_info = vim.loop.fs_stat(file)
    if file_info and file_info.type == 'file' then
      table.insert(files_with_sizes, {
        path = file,
        size = file_info.size
      })
    end
  end

  -- Step 4: Sort by file size (bigger to smaller)
  table.sort(files_with_sizes, function(a, b)
    return a.size > b.size
  end)

  -- Step 5: Extract just the file paths from the sorted list
  local final_files = {}
  for _, file_data in ipairs(files_with_sizes) do
    table.insert(final_files, file_data.path)
  end

  return final_files
end

function aiconfig.listScannedFilesAsText()
  local analyzed_files_as_array = aiconfig.listScannedFilesFromConfig()
  local num_files = #analyzed_files_as_array

  if num_files == 0 then
    return ""
  end

  local file_names = {}
  for _, file in ipairs(analyzed_files_as_array) do
    table.insert(file_names, string.format("`%%s`", file))
  end

  local analyzed_files_as_string = "The project is composed of " .. num_files .. " file" .. (num_files > 1 and "s" or "") .. ": "

  if num_files == 1 then
    analyzed_files_as_string = analyzed_files_as_string .. file_names[1] .. "."
  elseif num_files == 2 then
    analyzed_files_as_string = analyzed_files_as_string .. table.concat(file_names, " and ") .. "."
  else
    analyzed_files_as_string = analyzed_files_as_string .. table.concat(file_names, ", ", 1, num_files - 1) .. ", and " .. file_names[num_files] .. "."
  end

  return analyzed_files_as_string
end

function aiconfig.contentOf(file)
  local f = io.open(file, "r")
  if f then
    local filecontent = f:read("*all")
    f:close()
    return filecontent
  end
  return ""
end

function aiconfig.listScannedFiles()
  local analyzed_files_as_array = aiconfig.listScannedFilesFromConfig()
  if #analyzed_files_as_array == 0 then
    return "# No files to analyze under project root " .. aiconfig.getProjectRoot()
  end

  local analyzed_files_as_string = " will be analyzed under project root ".. aiconfig.getProjectRoot() .. ":\n"
  local total_size = 0 -- Initialize total size

  for _, file in ipairs(analyzed_files_as_array) do
    local stat = vim.loop.fs_stat(file)
    local size = stat and stat.size or 0 -- Default to 0 if size is unknown
    total_size = total_size + size -- Add file size to total

    local size_str = size .. " B"
    if size > 1024 then
      size_str = string.format("%.2f KB", size / 1024)
    end
    if size > 1024 * 1024 then
      size_str = string.format("%.2f MB", size / (1024 * 1024))
    end
    analyzed_files_as_string = analyzed_files_as_string .. "- " .. file .. " (Size: " .. size_str .. ")\n"
  end

  -- Format total size
  local total_size_str = total_size .. " B"
  if total_size > 1024 then
    total_size_str = string.format("%.2f KB", total_size / 1024)
  end
  if total_size > 1024 * 1024 then
    total_size_str = string.format("%.2f MB", total_size / (1024 * 1024))
  end

  -- Append total size to the string
  analyzed_files_as_string = "\n# A total of " .. total_size_str .. analyzed_files_as_string

  return analyzed_files_as_string
end

return aiconfig
```

## Changes Made:

The key changes are in the `listScannedFilesFromConfig()` function:

1. Instead of just collecting file paths and sorting them alphabetically, I've modified the function to:
   - Create a list of tables containing both the file path and its size
   - Sort this list by file size in descending order (bigger to smaller)
   - Extract just the file paths from the sorted list for the final return value

2. Steps added:
   ```lua
   -- Step 3: Create a list of files with their sizes
   local files_with_sizes = {}
   for file, _ in pairs(included_files) do
     local file_info = vim.loop.fs_stat(file)
     if file_info and file_info.type == 'file' then
       table.insert(files_with_sizes, {
         path = file,
         size = file_info.size
       })
     end
   end

   -- Step 4: Sort by file size (bigger to smaller)
   table.sort(files_with_sizes, function(a, b)
     return a.size > b.size
   end)

   -- Step 5: Extract just the file paths from the sorted list
   local final_files = {}
   for _, file_data in ipairs(files_with_sizes) do
     table.insert(final_files, file_data.path)
   end
   ```

3. Removed the original sorting line that sorted by filename:
   ```lua
   -- table.sort(final_files) -- This was removed
   ```

With these changes, the files will now be presented in order of size (largest first), which can help prioritize the most substantial files in the project when working with LLMs.

