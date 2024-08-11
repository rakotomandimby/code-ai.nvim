local aiconfig = {}

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
  local project_root = vim.fn.getcwd()
  return project_root
end

function aiconfig.listScannedFilesFromConfig()
  local config = aiconfig.findScannedFilesConfig()
  if config == "" then
    return {}
  end
  local patterns = {}
  for line in io.lines(config) do
    table.insert(patterns, line)
  end
  local files = {}
  for _, pattern in ipairs(patterns) do
    for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
      table.insert(files, file)
    end
  end
  return files
end

function aiconfig.listScannedFilesAsText()
  local analyzed_files_as_array = aiconfig.listScannedFilesFromConfig()
  if #analyzed_files_as_array == 0 then
    return ""
  end

  local analyzed_files_as_string = ""
  if 1 == #aiconfig.listScannedFilesFromConfig() then
    analyzed_files_as_string = "The project is composed of one file: " .. analyzed_files_as_array[1] .. "."
  end
  if 2 == #aiconfig.listScannedFilesFromConfig() then
    analyzed_files_as_string = "The project is composed of two files: " .. analyzed_files_as_array[1] .. " and " .. analyzed_files_as_array[2] .. "."
  end
  if 3 <= #aiconfig.listScannedFilesFromConfig() then
    analyzed_files_as_string = "The project is composed of " .. #aiconfig.listScannedFilesFromConfig() .. " files: "
  end
  for i, file in ipairs(analyzed_files_as_array) do
    if i == (#analyzed_files_as_array - 1) then
      analyzed_files_as_string = analyzed_files_as_string .. analyzed_files_as_array[#analyzed_files_as_array-1] .. " and " .. analyzed_files_as_array[#analyzed_files_as_array] .. "."
    else
      analyzed_files_as_string = analyzed_files_as_string .. analyzed_files_as_array[i] .. ", "
    end
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
