local history = {}
local aiconfig = require('ai.aiconfig')
local common = require('ai.common')

-- Create the '.ai-history' directory under the project root if it doesn't exist
function history.createHistoryDir()
    local historyDir = aiconfig.getProjectRoot() .. '/.ai-history'
    local historyDirExists = vim.fn.isdirectory(historyDir)
    if not historyDirExists then
        vim.fn.mkdir(historyDir, 'p')
    end
end

function history.saveToHistory(model, content)
    -- handle errors and log them
    if not pcall(history.createHistoryDir) then
        common.log("Error: Failed to create history directory")
        return
    end
    local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
    local fileName = model .. '_' .. timestamp .. ".md"
    local filePath = aiconfig.getProjectRoot() .. '/.ai-history/' .. fileName
    local file = io.open(filePath, "w")
    if file then
        file:write(content)
        file:close()
        return filePath
    else
        return nil
    end
end



return history
