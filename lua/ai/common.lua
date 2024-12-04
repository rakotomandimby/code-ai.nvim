local common = {}

function common.escapePercent(s)
  return string.gsub(s, "%%", "%%%%")
end

function common.log(message)
  local log_file = io.open("/tmp/aiconfig.log", "a")
  if not log_file then
    error("Could not open log file for writing.")
  end
  log_file:write(message .. "\n")
  log_file:close()
end


return common
