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
    history.removeOldestHistoryFiles()
    return filePath
  else
    return nil
  end
end

-- list files in the '.ai-history' directory, ordered by filename
function history.listHistoryFiles()
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  local files = vim.fn.readdir(historyDir)
  table.sort(files)
  for i, file in ipairs(files) do
    common.log("File " .. i .. ": " .. file)
  end
  return files
end

-- Do you this this function will do the expected thing of removing the oldest files?
-- Also check `history.listHistoryFiles()` to see if the order is correct
function history.removeOldestHistoryFiles()
  local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
  local files = history.listHistoryFiles()
  common.log("Files in history folder:")
  for i, file in ipairs(files) do
    common.log("File " .. i .. ": " .. file)
  end
  if #files > 10 then
    common.log(string.format("There are %%d files in the history folder", #files))
    common.log(string.format("We need to remove %%d files", #files - 10))
    for i = #files - 9, 1, -1 do  -- Corrected loop start index
      local file = files[i]
      local filePath = historyDir .. '/' .. file
      vim.fn.delete(filePath)
      common.log("Deleted oldest history file: " .. filePath)
    end
  else
    common.log("There are less than 10 files in the history folder")
  end
end

return history
