-- Enhanced Claude integration with MCP
-- ~/.config/nvim/lua/claude/init.lua

local M = {}
local curl = require("plenary.curl")
local json = require("claude.json")
local config = require("claude.config")

-- Default configuration
local default_config = {
  mcp_url = "http://127.0.0.1:5678",
  claude_api_key = "",
  claude_model = "claude-3-5-sonnet-20240229",
  max_tokens = 4096,
  history_size = 10
}

-- Initialize configuration
local function init_config()
  M.config = vim.tbl_deep_extend("force", default_config, config.load_claude_config() or {})
  return M.config
end

-- Initialize Claude window
local function init_window()
  local win_width = math.floor(vim.o.columns * 0.8)
  local win_height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - win_height) / 2)
  local col = math.floor((vim.o.columns - win_width) / 2)

  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  -- Create window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded'
  })

  -- Set window options
  vim.api.nvim_win_set_option(win, 'winblend', 0)
  vim.api.nvim_win_set_option(win, 'cursorline', true)

  return buf, win
end

-- Format message for Claude API
local function format_message(system_prompt, user_message, conversation_history)
  local messages = {}
  
  -- Add system message if provided
  if system_prompt and system_prompt ~= "" then
    table.insert(messages, {
      role = "system",
      content = system_prompt
    })
  end
  
  -- Add conversation history
  if conversation_history then
    for _, msg in ipairs(conversation_history) do
      table.insert(messages, msg)
    end
  end
  
  -- Add the current user message
  table.insert(messages, {
    role = "user",
    content = user_message
  })
  
  return messages
end

-- Function to fetch system information from MCP
function M.fetch_system_info()
  local conf = M.config or init_config()
  local response = curl.get({
    url = conf.mcp_url .. "/system/info",
    accept = "application/json"
  })
  
  if response.status ~= 200 then
    return nil, "Failed to fetch system info: " .. (response.body or "Unknown error")
  end
  
  return json.decode(response.body)
end

-- Function to fetch installed packages from MCP
function M.fetch_installed_packages()
  local conf = M.config or init_config()
  local response = curl.get({
    url = conf.mcp_url .. "/packages/installed",
    accept = "application/json"
  })
  
  if response.status ~= 200 then
    return nil, "Failed to fetch packages: " .. (response.body or "Unknown error")
  end
  
  return json.decode(response.body)
end

-- Create a system snapshot
function M.create_snapshot()
  local conf = M.config or init_config()
  local response = curl.post({
    url = conf.mcp_url .. "/snapshot/create",
    accept = "application/json",
    body = "{}"  -- Empty JSON object
  })
  
  if response.status ~= 200 then
    return nil, "Failed to create snapshot: " .. (response.body or "Unknown error")
  end
  
  return json.decode(response.body)
end

-- Function to execute a command via MCP (if enabled)
function M.execute_command(command)
  local conf = M.config or init_config()
  local response = curl.post({
    url = conf.mcp_url .. "/execute",
    accept = "application/json",
    body = json.encode({ command = command })
  })
  
  if response.status ~= 200 then
    return nil, "Failed to execute command: " .. (response.body or "Unknown error")
  end
  
  return json.decode(response.body)
end

-- Generate system context for Claude
function M.generate_system_context()
  local system_info, err_info = M.fetch_system_info()
  local packages, err_pkg = M.fetch_installed_packages()
  
  if not system_info then
    return "System information unavailable: " .. (err_info or "Unknown error")
  end
  
  local context = "You are Claude, an AI assistant integrated into TheArchHive for Arch Linux. "
    .. "You're running inside Neovim and have access to system information through the MCP server. "
    .. "You can help configure, optimize, and troubleshoot Arch Linux systems.\n\n"
    .. "Current system information:\n"
    .. "- Hostname: " .. (system_info.hostname or "Unknown") .. "\n"
    .. "- Kernel: " .. (system_info.os and system_info.os.kernel or "Unknown") .. "\n"
    .. "- CPU: " .. (system_info.cpu and system_info.cpu.model or "Unknown") .. " ("
    .. (system_info.cpu and system_info.cpu.cores or 0) .. " cores, "
    .. (system_info.cpu and system_info.cpu.threads or 0) .. " threads)\n"
    .. "- Memory: " .. (system_info.memory and system_info.memory.total_gb or 0) .. "GB total, "
    .. (system_info.memory and system_info.memory.used_gb or 0) .. "GB used ("
    .. (system_info.memory and system_info.memory.percent_used or 0) .. "%)\n"
    .. "- Disk: " .. (system_info.disk and system_info.disk.total_gb or 0) .. "GB total, "
    .. (system_info.disk and system_info.disk.used_gb or 0) .. "GB used ("
    .. (system_info.disk and system_info.disk.percent_used or 0) .. "%)\n"
  
  if system_info.gpu then
    context = context .. "- GPU: " .. system_info.gpu .. "\n"
  end
  
  if packages and packages.packages then
    context = context .. "\nSome key installed packages:\n"
    -- Only show a subset of important packages to avoid making the context too large
    local important_packages = {"linux", "base", "base-devel", "neovim", "vim", "emacs", "xorg", 
                               "wayland", "sway", "i3", "kde", "gnome", "firefox", "chromium"}
    local count = 0
    for _, pkg in ipairs(packages.packages) do
      for _, imp in ipairs(important_packages) do
        if pkg.name:find(imp) then
          context = context .. "- " .. pkg.name .. " (" .. pkg.version .. ")\n"
          count = count + 1
          break
        end
      end
      if count >= 10 then break end
    end
    context = context .. "\nTotal installed packages: " .. #packages.packages .. "\n"
  end
  
  context = context .. "\nYou can provide suggestions for system optimization, help with configuration, "
    .. "and troubleshoot issues. You can also create system snapshots and execute safe commands with user approval."
    .. "\n\nPlease be concise and tailor your responses to the user's setup as shown above."
  
  return context
end

-- Function to send message to Claude API
function M.send_message(user_message, display_callback, buf)
  local conf = M.config or init_config()

  -- Generate system context
  local system_context = M.generate_system_context()

  -- Initialize conversation history if not exists
  if not M.conversation_history then
    M.conversation_history = {}
  end

  -- Format messages - We need to separate system message from regular messages
  local messages = {}

  -- Add conversation history
  if M.conversation_history then
    for _, msg in ipairs(M.conversation_history) do
      table.insert(messages, msg)
    end
  end

  -- Add the current user message
  table.insert(messages, {
    role = "user",
    content = user_message
  })

  -- Build request body - Note that system message is a top-level parameter, not part of messages array
  local request_body = json.encode({
    model = conf.claude_model,
    max_tokens = conf.max_tokens,
    system = system_context, -- System message goes here as a top-level parameter
    messages = messages     -- Regular conversation messages here
  })

  -- Display thinking message
  if display_callback then
    display_callback(buf, "Thinking...")
  end

  -- Make API request
  local response = curl.post({
    url = "https://api.anthropic.com/v1/messages",
    headers = {
      ["x-api-key"] = conf.claude_api_key,
      ["anthropic-version"] = "2023-06-01",
      ["content-type"] = "application/json"
    },
    body = request_body
  })

  if response.status ~= 200 then
    local error_msg = "Error: " .. (response.body or "Unknown error")
    if display_callback then
      display_callback(buf, error_msg)
    end
    return nil, error_msg
  end

  local result = json.decode(response.body)

  -- Add message to conversation history
  table.insert(M.conversation_history, {
    role = "user",
    content = user_message
  })

  table.insert(M.conversation_history, {
    role = "assistant",
    content = result.content[1].text
  })

  -- Limit history size
  while #M.conversation_history > conf.history_size * 2 do
    table.remove(M.conversation_history, 1)
  end

  -- Display response
  if display_callback then
    display_callback(buf, result.content[1].text)
  end

  return result.content[1].text
end

-- Display message in buffer
function M.display_message(buf, message)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  
  local lines = {}
  for line in message:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

-- Function to handle user input
function M.handle_input(buf, win)
  local prompt = "Ask Claude: "
  local input = vim.fn.input({
    prompt = prompt,
    cancelreturn = "__CANCEL__"
  })
  
  if input == "__CANCEL__" or input == "" then
    return
  end
  
  -- Display user question
  M.display_message(buf, "You: " .. input .. "\n\nClaude: ")
  
  -- Send to Claude API
  M.send_message(input, function(buffer, response)
    if buffer and vim.api.nvim_buf_is_valid(buffer) then
      M.display_message(buffer, "You: " .. input .. "\n\nClaude: " .. response)
    end
  end, buf)
end

-- Initialize Claude
function M.init()
  -- Load configuration
  init_config()
  
  -- Create buffer and window
  local buf, win = init_window()
  
  -- Initial message
  local welcome_msg = [[
   ████████ ██   ██ ███████      █████  ██████   ██████ ██   ██     ██   ██ ██ ██    ██ ███████ 
      ██    ██   ██ ██          ██   ██ ██   ██ ██      ██   ██     ██   ██ ██ ██    ██ ██      
      ██    ███████ █████       ███████ ██████  ██      ███████     ███████ ██ ██    ██ █████   
      ██    ██   ██ ██          ██   ██ ██   ██ ██      ██   ██     ██   ██ ██  ██  ██  ██      
      ██    ██   ██ ███████     ██   ██ ██   ██  ██████ ██   ██     ██   ██ ██   ████   ███████ 
                                                                                                
  Welcome to TheArchHive with Claude integration!
  I'm ready to help you optimize your Arch Linux system.
  
  Press <Space>ca to ask a question or type any message below:
  ]]
  
  M.display_message(buf, welcome_msg)
  
  -- Set up keymaps
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Space>ca', 
    [[<Cmd>lua require('claude').handle_input(]] .. buf .. [[, ]] .. win .. [[)<CR>]], 
    {noremap = true, silent = true})
  
  return buf, win
end

-- Set up commands
function M.setup()
  vim.api.nvim_create_user_command('Claude', function()
    M.init()
  end, {})
  
  vim.api.nvim_create_user_command('ClaudeSnapshot', function()
    local snapshot, err = M.create_snapshot()
    if snapshot then
      print("Snapshot created: " .. (snapshot.snapshot_path or "unknown path"))
    else
      print("Failed to create snapshot: " .. (err or "Unknown error"))
    end
  end, {})
  
  -- Set up key bindings
  vim.api.nvim_set_keymap('n', '<Space>cc', '<Cmd>Claude<CR>', {noremap = true, silent = true})
end

return M
