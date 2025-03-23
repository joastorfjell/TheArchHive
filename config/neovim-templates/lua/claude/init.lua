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
  claude_model = "claude-3-7-sonnet-20250219",
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

-- Safer HTTP request function with error handling
local function make_http_request(url, method, options)
  -- Ensure method is uppercase
  method = string.upper(method or "GET")
  options = options or {}
  
  -- Set defaults
  options.timeout = options.timeout or 30000  -- 30 second timeout
  options.headers = options.headers or {}
  
  -- Create a protected call to curl
  local ok, result
  if method == "GET" then
    ok, result = pcall(function()
      return curl.get({
        url = url,
        accept = options.accept or "application/json",
        headers = options.headers,
        timeout = options.timeout
      })
    end)
  elseif method == "POST" then
    ok, result = pcall(function() 
      return curl.post({
        url = url,
        accept = options.accept or "application/json",
        headers = options.headers,
        body = options.body,
        timeout = options.timeout
      })
    end)
  else
    return nil, "Unsupported HTTP method: " .. method
  end
  
  if not ok then
    return nil, "HTTP request failed: " .. tostring(result)
  end
  
  return result, nil
end

-- Function to fetch system information from MCP
function M.fetch_system_info()
  local conf = M.config or init_config()
  
  local response, err = make_http_request(
    conf.mcp_url .. "/system/info", 
    "GET"
  )
  
  if err or not response or response.status ~= 200 then
    return nil, "Failed to fetch system info: " .. (err or (response and response.body or "Unknown error"))
  end
  
  local ok, parsed_body = pcall(json.decode, response.body)
  if not ok then
    return nil, "Failed to parse system info: " .. tostring(parsed_body)
  end
  
  return parsed_body, nil
end

-- Function to fetch installed packages from MCP
function M.fetch_installed_packages()
  local conf = M.config or init_config()
  
  local response, err = make_http_request(
    conf.mcp_url .. "/packages/installed", 
    "GET"
  )
  
  if err or not response or response.status ~= 200 then
    return nil, "Failed to fetch packages: " .. (err or (response and response.body or "Unknown error"))
  end
  
  local ok, parsed_body = pcall(json.decode, response.body)
  if not ok then
    return nil, "Failed to parse packages: " .. tostring(parsed_body)
  end
  
  return parsed_body, nil
end

-- Create a system snapshot
function M.create_snapshot()
  local conf = M.config or init_config()
  
  local response, err = make_http_request(
    conf.mcp_url .. "/snapshot/create", 
    "POST", 
    {body = "{}"}  -- Empty JSON object
  )
  
  if err or not response or response.status ~= 200 then
    return nil, "Failed to create snapshot: " .. (err or (response and response.body or "Unknown error"))
  end
  
  local ok, parsed_body = pcall(json.decode, response.body)
  if not ok then
    return nil, "Failed to parse snapshot response: " .. tostring(parsed_body)
  end
  
  return parsed_body, nil
end

-- Function to execute a command via MCP (if enabled)
function M.execute_command(command)
  local conf = M.config or init_config()
  
  local response, err = make_http_request(
    conf.mcp_url .. "/execute", 
    "POST", 
    {body = json.encode({ command = command })}
  )
  
  if err or not response or response.status ~= 200 then
    return nil, "Failed to execute command: " .. (err or (response and response.body or "Unknown error"))
  end
  
  local ok, parsed_body = pcall(json.decode, response.body)
  if not ok then
    return nil, "Failed to parse command response: " .. tostring(parsed_body)
  end
  
  return parsed_body, nil
end

-- Generate system context for Claude
function M.generate_system_context()
  local system_info, err_info = M.fetch_system_info()
  local packages, err_pkg = M.fetch_installed_packages()
  
  local context = "You are Claude, an AI assistant integrated into TheArchHive for Arch Linux. "
    .. "You're running inside Neovim and have access to system information through the MCP server. "
    .. "You can help configure, optimize, and troubleshoot Arch Linux systems.\n\n"
    .. "Current system information:\n"
  
  if not system_info then
    context = context .. "System information unavailable: " .. (err_info or "Unknown error") .. "\n"
  else
    context = context .. "- Hostname: " .. (system_info.hostname or "Unknown") .. "\n"
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
  end
  
  if not packages then
    context = context .. "\nPackage information unavailable: " .. (err_pkg or "Unknown error") .. "\n"
  elseif packages.packages then
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

-- Function to send message to Claude API (with better error handling)
function M.send_message(user_message, display_callback, buf)
  local conf = M.config or init_config()
  
  -- Generate system context
  local system_context = M.generate_system_context()
  
  -- Initialize conversation history if not exists
  if not M.conversation_history then
    M.conversation_history = {}
  end
  
  -- Format messages
  local messages = format_message(system_context, user_message, M.conversation_history)
  
  -- Build request body
  local request_body = json.encode({
    model = conf.claude_model,
    max_tokens = conf.max_tokens,
    messages = messages
  })
  
  -- Display thinking message
  if display_callback then
    display_callback(buf, "Thinking...")
  end
  
  -- Send API request with error handling
  local response, err = make_http_request(
    "https://api.anthropic.com/v1/messages",
    "POST",
    {
      headers = {
        ["x-api-key"] = conf.claude_api_key,
        ["anthropic-version"] = "2023-06-01",
        ["content-type"] = "application/json"
      },
      body = request_body
    }
  )
  
  if err or not response or response.status ~= 200 then
    local error_msg = "Error: " .. (err or (response and response.body or "Unknown error"))
    if display_callback then
      display_callback(buf, error_msg)
    end
    return nil, error_msg
  end
  
  -- Parse the response
  local ok, result = pcall(json.decode, response.body)
  if not ok then
    local error_msg = "Error parsing response: " .. tostring(result)
    if display_callback then
      display_callback(buf, error_msg)
    end
    return nil, error_msg
  end
  
  -- Check if result has the expected structure
  if not result or not result.content or not result.content[1] or not result.content[1].text then
    local error_msg = "Unexpected response format"
    if display_callback then
      display_callback(buf, error_msg)
    end
    return nil, error_msg
  end
  
  -- Get the actual response text
  local response_text = result.content[1].text
  
  -- Add message to conversation history
  table.insert(M.conversation_history, {
    role = "user",
    content = user_message
  })
  
  table.insert(M.conversation_history, {
    role = "assistant",
    content = response_text
  })
  
  -- Limit history size
  while #M.conversation_history > conf.history_size * 2 do
    table.remove(M.conversation_history, 1)
  end
  
  -- Display response
  if display_callback then
    display_callback(buf, response_text)
  end
  
  return response_text
end

-- Display message in buffer safely
function M.display_message(buf, message)
  -- Check if buffer exists and is valid
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    print("Error: Buffer is not valid")
    return
  end
  
  -- Ensure message is a string
  message = tostring(message or "")
  
  -- Split message into lines
  local lines = {}
  for line in message:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  
  -- If no lines, add an empty one
  if #lines == 0 then
    lines = {""}
  end
  
  -- Use pcall to safely set buffer lines
  local ok, err = pcall(function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end)
  
  if not ok then
    print("Error displaying message: " .. err)
  end
end

-- Function to handle user input
function M.handle_input(buf, win)
  -- Check if buffer exists and is valid
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    print("Error: Buffer is not valid")
    return
  end
  
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
  
  -- Send to Claude API with pcall for safety
  local ok, result_or_err = pcall(function()
    return M.send_message(input, function(buffer, response)
      if buffer and vim.api.nvim_buf_is_valid(buffer) then
        M.display_message(buffer, "You: " .. input .. "\n\nClaude: " .. response)
      end
    end, buf)
  end)
  
  if not ok then
    -- Handle error
    M.display_message(buf, "You: " .. input .. "\n\nError communicating with Claude: " .. tostring(result_or_err))
  end
end

-- Initialize Claude
function M.init()
  -- Load configuration
  init_config()
  
  -- Create buffer and window with error handling
  local ok, result = pcall(init_window)
  if not ok then
    print("Error initializing Claude window: " .. tostring(result))
    return nil, nil
  end
  
  -- Now result contains the actual return values from init_window,
  -- which are buf and win directly, not in a table
  local buf, win = result, nil
  
  if type(result) == "table" then
    -- If init_window returned a table, unpack it
    buf, win = unpack(result)
  end
  
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
  local ok, err = pcall(function()
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Space>ca', 
      string.format([[<Cmd>lua require('claude').handle_input(%d, %d)<CR>]], buf, win), 
      {noremap = true, silent = true})
  end)
  
  if not ok then
    print("Error setting up keymaps: " .. tostring(err))
  end
  
  return buf, win
end

-- Set up commands
function M.setup()
  vim.api.nvim_create_user_command('Claude', function()
    local ok, result = pcall(M.init)
    if not ok then
      print("Error running Claude: " .. tostring(result))
    end
  end, {})
  
  vim.api.nvim_create_user_command('ClaudeSnapshot', function()
    local ok, result_or_err = pcall(function()
      local snapshot, err = M.create_snapshot()
      if snapshot then
        print("Snapshot created: " .. (snapshot.snapshot_path or "unknown path"))
      else
        print("Failed to create snapshot: " .. (err or "Unknown error"))
      end
    end)
    
    if not ok then
      print("Error creating snapshot: " .. tostring(result_or_err))
    end
  end, {})
  
  -- Set up key bindings
  vim.api.nvim_set_keymap('n', '<Space>cc', '<Cmd>Claude<CR>', {noremap = true, silent = true})
end

return M
