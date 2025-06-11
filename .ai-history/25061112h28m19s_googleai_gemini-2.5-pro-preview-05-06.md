1.  **Bug in `history.lua` (`removeOldestHistoryFiles`)**:
    *   The current loop logic for removing old history files appears to be incorrect.
    *   `files` are sorted chronologically (oldest first).
    *   The goal is to keep `numberOfFilesToKeep` and remove `#files - numberOfFilesToKeep` oldest files.
    *   The loop `for i = #files - (numberOfFilesToKeep -1), 1, -1 do` seems to have an off-by-one issue or incorrect bounds. For example, if `#files = 5` and `numberOfFilesToKeep = 3`, we want to remove 2 files (`files[1]` and `files[2]`). The loop runs for `i = 3, 2, 1`, deleting `files[3]`, `files[2]`, and `files[1]`, thus deleting 3 files instead of 2.
    *   A simpler and correct loop would be:
        ```lua
        local files_to_remove_count = #files - numberOfFilesToKeep
        if files_to_remove_count > 0 then
          for i = 1, files_to_remove_count do
            local file_to_delete = files[i] -- files[1] is the oldest
            local filePath = historyDir .. '/' .. file_to_delete
            vim.fn.delete(filePath)
            common.log("Deleted oldest history file: " .. filePath)
          end
        end
        ```
    *   This needs to be addressed to ensure correct history cleanup.



# Fix bug in history file cleanup logic

We will fix a bug in the `removeOldestHistoryFiles` function within `lua/ai/history.lua`. The existing loop for deleting older history files was incorrect, potentially deleting more files than intended or the wrong files. The corrected logic will accurately calculate the number of oldest files to remove and iterate from the beginning of the sorted list (oldest files first) to delete them.

## `lua/ai/history.lua`

We will modify the `removeOldestHistoryFiles` function to correctly identify and remove the oldest history files, ensuring that only the excess files beyond `numberOfFilesToKeep` are deleted. The files are sorted chronologically, so the oldest files are at the beginning of the list.

```lua
local history = {}
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')

-- Create the '.ai-history' directory under the project root if it doesn't exist
function history.createHistoryDir()
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  common.log("Checking if history directory exists: " .. historyDir)
  local historyDirExists = vim.fn.isdirectory(historyDir) == 1
  if not historyDirExists then
    vim.fn.mkdir(historyDir, 'p')
    common.log("Created history directory: " .. historyDir)
  end
end

function history.saveToHistory(model, content)
  common.log("Saving history to " .. model .. " history file")
  history.createHistoryDir()
  common.log("Creating history file for " .. model)
  local fileName = os.date("%Y%m%d%Hh%Mm%Ss") .. "_" .. model .. ".md"
  -- remove the 2 first characters of the filename, because it is century and we dont need it
  fileName = string.sub(fileName, 3)
  local filePath = aiconfig.getProjectRoot() .. '/.ai-history/' .. fileName
  local file = io.open(filePath, "w")
  common.log("Writing to history file: " .. filePath)
  if file then
    file:write(content)
    file:close()
    history.removeOldestHistoryFiles(15)
    return filePath
  else
    return nil
  end
end

-- list files in the '.ai-history' directory, ordered by filename
function history.listHistoryFiles()
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  local files = vim.fn.readdir(historyDir)
  -- Filter out any potential subdirectories or non-file entries if readdir could include them
  local filtered_files = {}
  for _, file_or_dir_name in ipairs(files) do
    if vim.fn.filereadable(historyDir .. '/' .. file_or_dir_name) == 1 then
      table.insert(filtered_files, file_or_dir_name)
    end
  end
  table.sort(filtered_files) -- Sorts alphabetically, which works for YYMMDD filenames
  common.log("Sorted history files:")
  for i, file_name in ipairs(filtered_files) do
    common.log("File " .. i .. ": " .. file_name)
  end
  return filtered_files
end

-- Removes the oldest history files if the total number exceeds numberOfFilesToKeep.
-- Files are assumed to be sorted chronologically by listHistoryFiles (oldest first).
function history.removeOldestHistoryFiles(numberOfFilesToKeep)
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  local files = history.listHistoryFiles()

  common.log(string.format("Found %d history files. Keeping a maximum of %d files.", #files, numberOfFilesToKeep))

  if #files > numberOfFilesToKeep then
    local files_to_remove_count = #files - numberOfFilesToKeep
    common.log(string.format("Need to remove %d oldest files.", files_to_remove_count))

    for i = 1, files_to_remove_count do
      -- Since files are sorted oldest first, files[1], files[2], etc., are the oldest.
      local file_to_delete = files[i]
      if file_to_delete then -- Ensure the file entry exists
        local filePath = historyDir .. '/' .. file_to_delete
        local success, err = vim.fn.delete(filePath)
        if success == 0 then -- vim.fn.delete returns 0 on success
          common.log("Deleted oldest history file: " .. filePath)
        else
          common.log("Error deleting history file: " .. filePath .. " - " .. (err or "Unknown error"))
        end
      else
        common.log("Warning: Tried to access a nil file entry at index " .. i .. " while removing old history files.")
      end
    end
  else
    common.log("Number of history files (" .. #files .. ") does not exceed the limit (" .. numberOfFilesToKeep .. "). No files removed.")
  end
end

return history

```

GoogleAI (18k in, 1k out)

