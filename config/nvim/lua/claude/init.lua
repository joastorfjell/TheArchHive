local M = {}

-- Create a new split for Claude
function M.open_claude()
  vim.cmd('vnew')
  vim.cmd('setlocal buftype=nofile')
  vim.cmd('setlocal bufhidden=hide')
  vim.cmd('setlocal noswapfile')
  vim.cmd('file Claude')
  
  -- Welcome message
  local lines = {
    "Hey, I'm Claude! What's your Arch setup goal?",
    "",
    "Type your questions below and press <leader>ca to ask me.",
    "----------------------------------------------------",
    ""
  }
  
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

-- Read system info
function M.get_system_info()
  -- Try to read the latest snapshot if it exists
  local snapshot_file = os.getenv("HOME") .. "/.TheArchHive/latest_snapshot.txt"
  local f = io.open(snapshot_file, "r")
  
  if f then
    local content = f:read("*all")
    f:close()
    return content
  else
    -- Fallback to reading CPU info directly
    local cpu_f = io.open("/proc/cpuinfo", "r")
    if cpu_f then
      local cpu_info = {}
      for line in cpu_f:lines() do
        if line:match("^model name") then
          table.insert(cpu_info, line:gsub("model name%s*:%s*", ""))
          break
        end
      end
      cpu_f:close()
      
      -- Get memory info
      local mem_info = "Unknown"
      local mem_f = io.popen("free -h | grep Mem | awk '{print $2}'")
      if mem_f then
        mem_info = mem_f:read("*all"):gsub("[\n\r]", "")
        mem_f:close()
      end
      
      return string.format("CPU: %s\nMemory: %s", cpu_info[1] or "Unknown", mem_info)
    else
      return "Could not read system information"
    end
  end
end

-- Parse Claudescript
function M.parse_claudescript(text)
  local result = {}
  for line in text:gmatch("[^\r\n]+") do
    if line:match("^p:") then
      local package = line:gsub("^p:", "")
      table.insert(result, "Package: " .. package)
    elseif line:match("^k:") then
      local kernel = line:gsub("^k:", "")
      table.insert(result, "Kernel: " .. kernel)
    elseif line:match("^c:") then
      local cpu = line:gsub("^c:", "")
      table.insert(result, "CPU: " .. cpu)
    elseif line:match("^m:") then
      local memory = line:gsub("^m:", "")
      table.insert(result, "Memory: " .. memory)
    end
  end
  
  return table.concat(result, "\n")
end

-- Simple hardcoded responses for the MVD
function M.ask_claude()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  
  -- Find the last question (after the last response)
  local question = ""
  local in_question = false
  
  for i = #lines, 1, -1 do
    if lines[i]:match("^Claude:") then
      break
    elseif lines[i] ~= "" then
      question = lines[i] .. " " .. question
      in_question = true
    elseif in_question then
      break
    end
  end
  
  -- Trim the question
  question = question:gsub("^%s+", ""):gsub("%s+$", "")
  
  -- Simple pattern matching responses
  local response = "I'm not sure about that yet. My capabilities are limited in this MVP."
  
  if question:lower():match("package") or question:lower():match("install") then
    response = "For coding, I recommend installing: neovim, gcc, python, git, and ripgrep."
  elseif question:lower():match("neovim") or question:lower():match("config") then
    response = "For a good Neovim setup, start with a plugin manager like Packer and add telescope for fuzzy finding."
  elseif question:lower():match("backup") or question:lower():match("github") then
    response = "To back up your configs, create a Git repository and commit your dotfiles regularly."
  elseif question:lower():match("optimization") or question:lower():match("performance") then
    response = "To optimize your Arch system, consider using the performance governor and installing tlp for battery savings."
  elseif question:lower():match("system") or question:lower():match("info") or question:lower():match("snapshot") then
    local system_info = M.get_system_info()
    local parsed_info = M.parse_claudescript(system_info)
    response = "Here's your system information:\n\n" .. parsed_info
  end
  
  -- Add the response
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, {"", "Claude: " .. response, ""})
end

-- Set up commands and keymaps
function M.setup()
  vim.api.nvim_create_user_command("Claude", M.open_claude, {})
  vim.keymap.set('n', '<leader>cc', M.open_claude, {noremap = true, desc = "Open Claude"})
  vim.keymap.set('n', '<leader>ca', M.ask_claude, {noremap = true, desc = "Ask Claude"})
end

return M
