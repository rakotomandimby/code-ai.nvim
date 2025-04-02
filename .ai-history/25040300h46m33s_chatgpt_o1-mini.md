# Make `aiconfig.listScannedFilesAsFormattedTable()` print a beautiful table 

The current implementation of `aiconfig.listScannedFilesAsFormattedTable()` prints two lists of files in two tabble column.

- Values are accurate
- First column formatting is correct
- Second column formatting is wrong: the right border of the second column is not aligned at all.

I guess if the first column left and right borders are aligned, 
the maximum width of the content has been calculated somewhere 
so that the second column alignement could leverage it.

Propose a solution to fix the second column right border alignment.



# This is o1-mini answer (12k in, 2k out)

To ensure both columns in your Markdown table are beautifully aligned, you need to calculate and apply padding for **both** columns based on their maximum content widths. Here's a step-by-step guide to achieve this:

1. **Calculate Maximum Widths for Both Columns:**
   - **First Column (`Sorted by Size (Desc)`):** You've already implemented this by determining `max_width_col1`.
   - **Second Column (`Sorted by Name (Asc)`):** Similarly, calculate `max_width_col2` by iterating through the sorted file names and finding the longest string.

2. **Adjust Headers and Separator Lines:**
   - Ensure both headers are padded according to their respective maximum widths.
   - Create separator lines (`---`) that match the width of each column.

3. **Format Each Row with Proper Padding:**
   - When inserting each row, pad both columns to align their content based on the calculated maximum widths.

4. **Helper Function for Padding:**
   - Create a helper function to pad strings to a desired length, ensuring consistent alignment.

Here's the revised implementation of `aiconfig.listScannedFilesAsFormattedTable()` incorporating these steps:

```lua
function aiconfig.listScannedFilesAsFormattedTable()
  local analyzed_files_paths = aiconfig.listScannedFilesFromConfig()
  local project_root = aiconfig.getProjectRoot()

  if #analyzed_files_paths == 0 then
    return "# No files to analyze under project root " .. project_root
  end

  local files_data = {}
  local total_size = 0
  local max_width_col1 = 0 -- Max width for the first column
  local max_width_col2 = 0 -- Max width for the second column

  -- Gather file data and calculate total size
  for _, relative_path in ipairs(analyzed_files_paths) do
    local full_path = project_root .. '/' .. relative_path
    local stat = vim.loop.fs_stat(full_path)
    local size = stat and stat.size or 0
    total_size = total_size + size
    local size_str = format_size(size)
    local display_str = relative_path .. " (" .. size_str .. ")"

    table.insert(files_data, {
      path = relative_path,
      size = size,
      size_str = size_str,
      display_str = display_str -- Display string for the first column
    })

    -- Update max width for the first column
    if #display_str > max_width_col1 then
      max_width_col1 = #display_str
    end
  end

  -- Sort files by size descending
  table.sort(files_data, function(a, b)
    return a.size > b.size
  end)

  -- Create a sorted copy for the second column (sorted by name ascending)
  local sorted_by_name = {}
  for _, data in ipairs(files_data) do
    table.insert(sorted_by_name, data)
  end
  table.sort(sorted_by_name, function(a, b)
    return a.path < b.path
  end)

  -- Determine the maximum width for the second column
  for _, data in ipairs(sorted_by_name) do
    if #data.path > max_width_col2 then
      max_width_col2 = #data.path
    end
  end

  -- Helper function to pad strings
  local function pad(str, length)
    if #str < length then
      return str .. string.rep(' ', length - #str)
    else
      return str
    end
  end

  -- Format total size
  local total_size_str = format_size(total_size)

  -- Build the Markdown table
  local result_lines = {}
  table.insert(result_lines, "# A total of " .. total_size_str .. " will be analyzed under project root " .. project_root .. ":\n")

  -- Define headers with proper padding
  local header1 = "Sorted by Size (Desc)"
  local header2 = "Sorted by Name (Asc)"
  local padded_header1 = pad(header1, max_width_col1)
  local padded_header2 = pad(header2, max_width_col2)

  table.insert(result_lines, "| " .. padded_header1 .. " | " .. padded_header2 .. " |")

  -- Define separator lines
  local separator1 = string.rep('-', max_width_col1)
  local separator2 = string.rep('-', max_width_col2)
  table.insert(result_lines, "|-" .. separator1 .. "-|-" .. separator2 .. "-|")

  -- Add table rows
  for i = 1, math.max(#files_data, #sorted_by_name) do
    local item_size = files_data[i]
    local item_name = sorted_by_name[i]

    -- Handle cases where the number of items might differ
    local col1 = item_size and pad(item_size.display_str, max_width_col1) or string.rep(' ', max_width_col1)
    local col2 = item_name and pad(item_name.path, max_width_col2) or string.rep(' ', max_width_col2)

    table.insert(result_lines, "| " .. col1 .. " | " .. col2 .. " |")
  end

  return table.concat(result_lines, "\n")
end
```

### Detailed Explanation of Changes:

1. **Calculating Maximum Width for the Second Column:**
   ```lua
   -- Determine the maximum width for the second column
   for _, data in ipairs(sorted_by_name) do
     if #data.path > max_width_col2 then
       max_width_col2 = #data.path
     end
   end
   ```

   After sorting the files by size, we create a sorted copy `sorted_by_name` and iterate through it to find the longest file path, updating `max_width_col2` accordingly.

2. **Helper Function for Padding:**
   ```lua
   local function pad(str, length)
     if #str < length then
       return str .. string.rep(' ', length - #str)
     else
       return str
     end
   end
   ```

   This function ensures that each cell's content is padded with spaces to match the desired column width, maintaining alignment.

3. **Adjusting Headers and Separator Lines:**
   ```lua
   -- Define headers with proper padding
   local header1 = "Sorted by Size (Desc)"
   local header2 = "Sorted by Name (Asc)"
   local padded_header1 = pad(header1, max_width_col1)
   local padded_header2 = pad(header2, max_width_col2)

   table.insert(result_lines, "| " .. padded_header1 .. " | " .. padded_header2 .. " |")

   -- Define separator lines
   local separator1 = string.rep('-', max_width_col1)
   local separator2 = string.rep('-', max_width_col2)
   table.insert(result_lines, "|-" .. separator1 .. "-|-" .. separator2 .. "-|")
   ```

   Both headers are padded to align with their respective column widths. The separator lines (`---`) are also adjusted based on these widths.

4. **Formatting Each Row with Proper Padding:**
   ```lua
   for i = 1, math.max(#files_data, #sorted_by_name) do
     local item_size = files_data[i]
     local item_name = sorted_by_name[i]

     -- Handle cases where the number of items might differ
     local col1 = item_size and pad(item_size.display_str, max_width_col1) or string.rep(' ', max_width_col1)
     local col2 = item_name and pad(item_name.path, max_width_col2) or string.rep(' ', max_width_col2)

     table.insert(result_lines, "| " .. col1 .. " | " .. col2 .. " |")
   end
   ```

   Each row now properly pads both columns, ensuring the right borders are aligned. The use of `math.max` ensures that even if the two sorted lists have different lengths (which shouldn't be the case in your current setup), the loop handles it gracefully.

5. **Final Output:**
   The function concatenates all the `result_lines` using `\n` to form the complete Markdown table, which will now have both columns nicely aligned.

### Example Output:

Assuming you have the following files:

- `main.lua (15 KB)`
- `init.lua (10 KB)`
- `utils.lua (20 KB)`

The generated Markdown table would look like:

```markdown
# A total of 45 KB will be analyzed under project root /path/to/project:

| Sorted by Size (Desc)   | Sorted by Name (Asc) |
|------------------------|----------------------|
| utils.lua (20 KB)      | init.lua             |
| main.lua (15 KB)       | main.lua             |
| init.lua (10 KB)       | utils.lua            |
```

### Additional Recommendations:

- **Dynamic Column Count Handling:** Ensure that both sorted lists (`sorted_by_size` and `sorted_by_name`) have the same number of elements. If not, decide how you want to handle extra rows.
  
- **Formatting Enhancements:** Consider using Markdown features like bold headers or different alignments for better readability.

- **Edge Cases:** Handle cases where file names might contain special Markdown characters that could disrupt table formatting.

By implementing these changes, your Markdown table should display both columns with properly aligned borders, enhancing its visual appeal and readability.

