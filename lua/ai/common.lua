    local common = {}

    function common.escapePercent(s)
      return string.gsub(s, "%%", "%%%%")
    end

    return common
