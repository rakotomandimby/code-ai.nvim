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

  common.log("Writing to history file: " .. filePath)
  -- vim.fn.writefile expects a list of strings (lines).
  -- The `true` in vim.split keeps trailing empty lines, which might be important for Markdown.
  local lines_to_write = vim.split(content, '\n')

  if vim.fn.writefile(lines_to_write, filePath) == 0 then
    common.log("Successfully wrote history file: " .. filePath)
    history.removeOldestHistoryFiles(15)
    return filePath
  else
    common.log("Failed to write history file: " .. filePath)
    return nil
  end
end

-- list files in the '.ai-history' directory, ordered by filename
function history.listHistoryFiles()
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  if vim.fn.isdirectory(historyDir) ~= 1 then
    common.log("History directory does not exist: " .. historyDir)
    return {}
  end
  local files = vim.fn.readdir(historyDir)
  table.sort(files)
  return files
end

-- Remove the oldest history files to keep only the specified number of most recent files
function history.removeOldestHistoryFiles(numberOfFilesToKeep)
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  local files = history.listHistoryFiles()

  if #files == 0 and vim.fn.isdirectory(historyDir) ~= 1 then
    -- listHistoryFiles already logged this, or directory doesn't exist.
    return
  end

  common.log("Files in history folder (" .. #files .. " total):")
  for i, file in ipairs(files) do
    common.log("File " .. i .. ": " .. file)
  end

  local files_to_remove_count = #files - numberOfFilesToKeep
  if files_to_remove_count > 0 then
    common.log(string.format("Need to remove %d oldest files to keep %d.", files_to_remove_count, numberOfFilesToKeep))
    -- Delete the oldest files (which are at the beginning of the sorted array)
    for i = 1, files_to_remove_count do
      local file_to_delete = files[i]
      local filePath_to_delete = historyDir .. '/' .. file_to_delete
      if vim.fn.delete(filePath_to_delete) == 0 then
        common.log("Deleted oldest history file: " .. filePath_to_delete)
      else
        common.log("Failed to delete history file: " .. filePath_to_delete)
      end
    end
  else
    common.log("No old history files to remove (found " .. #files .. ", keeping " .. numberOfFilesToKeep .. ").")
  end
end

return history

