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
  local fileName = os.date("%Y-%m-%d_%Hh-%Mm-%Ss") .. "_" .. model .. "_" .. string.format("%04d", os.time()) .. ".md"
  local filePath = aiconfig.getProjectRoot() .. '/.ai-history/' .. fileName
  local file = io.open(filePath, "w")
  common.log("Writing to history file: " .. filePath)
  if file then
    file:write(content)
    file:close()
    return filePath
  else
    return nil
  end
end

return history
