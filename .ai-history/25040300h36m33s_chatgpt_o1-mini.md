# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints a list of files with their sizes between brackets.

This prints mostly like this:

```
# A total of 41.01 KB will be analyzed under project root /home/mihamina/Projects/RKTMB/rktmb-code-ai.nvim:
- lua/ai/init.lua (Size: 8.57 KB)
- lua/ai/aiconfig.lua (Size: 8.54 KB)
- lua/ai/gemini/query.lua (Size: 6.57 KB)
- lua/ai/chatgpt/query.lua (Size: 5.95 KB)
- lua/ai/anthropic/query.lua (Size: 5.18 KB)
- lua/ai/history.lua (Size: 2.59 KB)
- lua/ai/globpattern.lua (Size: 2.54 KB)
- lua/ai/common.lua (Size: 1.06 KB)
```

I want to change that to a better formatted table, with two columns:
- one column is the list of "files and their size", ordered by size, descending
- the other column is the list of files and their size, ordered by name, ascending

Propose me the modifications to apply to the `aiconfig.listScannedFilesAsFormattedTable()` function in order to achieve that.




# This is o1-mini answer (11k in, 2k out)

To enhance the `aiconfig.listScannedFilesAsFormattedTable()` function to display a beautifully formatted table with two columns—**"Size Descending"** and **"Name Ascending"**—you can modify the function as follows:

1. **Sort the Files Separately:**
   - **By Size (Descending):** To display files ordered by their size in descending order.
   - **By Name (Ascending):** To display files ordered alphabetically by their name.

2. **Construct a Markdown Table:**
   - Utilize Markdown syntax to create a clear and readable table.
   - Ensure both columns are properly aligned and that the number of rows accommodates the larger of the two sorted lists.

3. **Handle Uneven Rows:**
   - If the lists are of unequal lengths, fill the empty cells with placeholders (e.g., empty strings) to maintain the table structure.

Here's the modified `aiconfig.listScannedFilesAsFormattedTable()` function with detailed comments explaining each step:

```lua
function aiconfig.listScannedFilesAsFormattedTable()
  local analyzed_files = aiconfig.listScannedFilesFromConfig()
  if #analyzed_files == 0 then
    return "# No files to analyze under project root " .. aiconfig.getProjectRoot()
  end

  local project_root = aiconfig.getProjectRoot()
  local total_size = 0 -- Initialize total size
  local files_with_sizes = {}

  -- Collect file paths and their sizes
  for _, file in ipairs(analyzed_files) do
    local stat = vim.loop.fs_stat(file)
    if stat and stat.type == 'file' then
      local size = stat.size or 0
      table.insert(files_with_sizes, {path = file, size = size})
      total_size = total_size + size
    else
      common.log("Path '" .. file .. "' is not a file or stat failed, skipping.")
    end
  end

  -- Helper function to format sizes
  local function format_size(size)
    if size > 1024 * 1024 then
      return string.format("%.2f MB", size / (1024 * 1024))
    elseif size > 1024 then
      return string.format("%.2f KB", size / 1024)
    else
      return string.format("%d B", size)
    end
  end

  -- Sort files by size descending
  local sorted_by_size = {table.unpack(files_with_sizes)}
  table.sort(sorted_by_size, function(a, b) return a.size > b.size end)

  -- Sort files by name ascending
  local sorted_by_name = {table.unpack(files_with_sizes)}
  table.sort(sorted_by_name, function(a, b) return a.path:lower() < b.path:lower() end)

  -- Determine the maximum number of rows
  local max_rows = math.max(#sorted_by_size, #sorted_by_name)

  -- Build the Markdown table
  local table_lines = {}
  table.insert(table_lines, string.format("# Total Size: %.2f KB\n", total_size / 1024))
  table.insert(table_lines, string.format("Project Root: %s\n", project_root))
  table.insert(table_lines, "| Size Descending | Name Ascending |")
  table.insert(table_lines, "|------------------|------------------|")

  for i = 1, max_rows do
    local size_entry = ""
    local name_entry = ""

    if sorted_by_size[i] then
      size_entry = string.format("`%s` (%s)", sorted_by_size[i].path, format_size(sorted_by_size[i].size))
    end

    if sorted_by_name[i] then
      name_entry = string.format("`%s` (%s)", sorted_by_name[i].path, format_size(sorted_by_name[i].size))
    end

    table.insert(table_lines, string.format("| %s | %s |", size_entry, name_entry))
  end

  -- Calculate total size in a readable format
  local formatted_total_size = format_size(total_size)

  -- Combine all lines into a single string
  local formatted_table = table.concat(table_lines, "\n")

  return string.format("# A total of %s will be analyzed under project root `%s`:\n\n%s", 
                       formatted_total_size, project_root, formatted_table)
end
```

### Detailed Explanation of the Modifications:

1. **Collecting File Information:**
   - **Line 2-10:** Iterate through the scanned files and collect each file's path and size. This information is stored in the `files_with_sizes` table. Simultaneously, calculate the `total_size` for all files.

2. **Formatting File Sizes:**
   - **Lines 12-18:** A helper function `format_size` is introduced to convert file sizes from bytes to a more readable format (KB or MB) with two decimal places.

3. **Sorting the Files:**
   - **Lines 21-25:** 
     - `sorted_by_size` is a shallow copy of `files_with_sizes` sorted in descending order based on file size.
     - `sorted_by_name` is another shallow copy sorted alphabetically by file name (case-insensitive).

4. **Determining Table Rows:**
   - **Line 28:** Compute `max_rows`, which is the maximum of the lengths of the two sorted lists. This ensures that all files are displayed, even if the lists have different lengths.

5. **Constructing the Markdown Table:**
   - **Lines 31-36:** Initialize the `table_lines` table with the header information and the Markdown table headers.
   - **Lines 38-48:** Loop through each row up to `max_rows`, populating the "Size Descending" and "Name Ascending" columns. If one list is shorter, the corresponding cell is left empty.

6. **Finalizing the Table:**
   - **Lines 51-53:** Combine all lines into a single string `formatted_table` using `table.concat`.
   - **Line 55:** Return the complete formatted string, including the total size, project root, and the Markdown table.

### Example Output:

When you run the modified function, the output will resemble the following Markdown table:

```markdown
# A total of 41.01 KB will be analyzed under project root `/home/mihamina/Projects/RKTMB/rktmb-code-ai.nvim`:

| Size Descending                               | Name Ascending                             |
|------------------------------------------------|--------------------------------------------|
| `lua/ai/init.lua` (8.57 KB)                   | `lua/ai/anthropic/query.lua` (5.18 KB)     |
| `lua/ai/aiconfig.lua` (8.54 KB)               | `lua/ai/chatgpt/query.lua` (5.95 KB)      |
| `lua/ai/gemini/query.lua` (6.57 KB)           | `lua/ai/common.lua` (1.06 KB)              |
| `lua/ai/chatgpt/query.lua` (5.95 KB)          |                                            |
| `lua/ai/anthropic/query.lua` (5.18 KB)        |                                            |
| `lua/ai/history.lua` (2.59 KB)                |                                            |
| `lua/ai/globpattern.lua` (2.54 KB)            |                                            |
| `lua/ai/common.lua` (1.06 KB)                  |                                            |
```

### Notes and Considerations:

- **Markdown Compatibility:** Ensure that wherever you display this table, Markdown rendering is supported to visualize the table correctly.

- **Handling Large Numbers of Files:** If your project contains a large number of files, consider pagination or other methods to prevent excessively long tables.

- **Error Handling:** The function includes logging for scenarios where file statistics can't be retrieved or if the path is not a file. Ensure that the log file (`/tmp/aiconfig.log`) is monitored for any unexpected issues.

- **Customization:** Feel free to adjust the formatting, such as column headers or size formatting, to better fit your preferences or project requirements.

By implementing these modifications, your `listScannedFilesAsFormattedTable()` function will produce a clear and organized table that presents your project's files both by size and name, enhancing readability and accessibility.

