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

-- Keep track of processed scripts to avoid duplicates
M.processed_scripts = {}

-- Simple hash function for script tracking
function M.simple_hash(str)
  local hash = 0
  for i = 1, #str do
    hash = ((hash * 31) + string.byte(str, i)) % 2147483647
  end
  return tostring(hash)
end

-- Initialize configuration
local function init_config()
  M.config = vim.tbl_deep_extend("force", default_config, config.load_claude_config() or {})
  return M.config
end

-- Initialize window
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
  
  return messages, system_prompt
end

-- Safer HTTP request function with improved timeout handling
local function make_http_request(url, method, options)
  -- Ensure method is uppercase
  method = string.upper(method or "GET")
  options = options or {}
  
  -- Set defaults with increased timeout
  options.timeout = options.timeout or 60000  -- 60 second timeout (was 30s)
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
  
  -- Handle timeout explicitly
  if result.status == 28 then -- CURLE_OPERATION_TIMEDOUT
    return nil, "Request timed out. Try with a shorter message or try again later."
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

-- Function to fetch window manager info
function M.fetch_window_manager_info()
  local conf = M.config or init_config()
  
  local response, err = make_http_request(
    conf.mcp_url .. "/system/windowmanager", 
    "GET"
  )
  
  if err or not response or response.status ~= 200 then
    -- Window manager endpoint might not exist yet
    return nil, "Failed to fetch window manager info: " .. (err or (response and response.body or "Unknown error"))
  end
  
  local ok, parsed_body = pcall(json.decode, response.body)
  if not ok then
    return nil, "Failed to parse window manager info: " .. tostring(parsed_body)
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
  local wm_info, err_wm = M.fetch_window_manager_info()
  
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
    context = context .. "\nInstalled packages:\n"
    -- Include up to 20 packages in the context
    local package_count = math.min(20, #packages.packages)
    for i = 1, package_count do
      local pkg = packages.packages[i]
      context = context .. "- " .. pkg.name .. " (" .. pkg.version .. ")\n"
    end
    context = context .. "\nTotal installed packages: " .. #packages.packages .. "\n"
  end
  
  -- Add window manager information if available
  if wm_info and wm_info.detected then
    context = context .. "\nWindow Manager: " .. wm_info.name .. " (" .. wm_info.status .. ")\n"
  end
  
  context = context .. "\nYou can provide suggestions for system optimization, help with configuration, "
    .. "and troubleshoot issues. You can also create system snapshots and execute safe commands with user approval."
    .. "\n\nPlease be concise and tailor your responses to the user's setup as shown above."
  
  return context
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

-- Function to send message to Claude API (with better error and timeout handling)
function M.send_message(user_message, display_callback, buf)
  local conf = M.config or init_config()
  
  -- Generate system context
  local system_context = M.generate_system_context()
  
  -- Initialize conversation history if not exists
  if not M.conversation_history then
    M.conversation_history = {}
  end
  
  -- Format messages
  local messages, system_prompt = format_message(system_context, user_message, M.conversation_history)
  
  -- Build request body with system at the top level
  local request_body = json.encode({
    model = conf.claude_model,
    max_tokens = conf.max_tokens,
    system = system_prompt,
    messages = messages
  })
  
  -- Display thinking message
  if display_callback then
    display_callback(buf, "Thinking...")
  end
  
  -- Send API request with improved error handling
  local response, err = make_http_request(
    "https://api.anthropic.com/v1/messages",
    "POST",
    {
      headers = {
        ["x-api-key"] = conf.claude_api_key,
        ["anthropic-version"] = "2023-06-01",
        ["content-type"] = "application/json"
      },
      body = request_body,
      timeout = 60000  -- Explicitly set 60s timeout for Claude API calls
    }
  )
  
  if err or not response or response.status ~= 200 then
    local error_msg
    if err and err:find("timed out") then
      error_msg = "The request to Claude API timed out. Please try again with a shorter message or wait a moment before retrying."
    else
      error_msg = "Error: " .. (err or (response and response.body or "Unknown error"))
    end
    
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
      
      -- Check for scripts in response
      M.offer_script_execution(buffer, response)
    end
  end, buf)
end

-- Extract multiple scripts from Claude's response
function M.extract_scripts(text)
  local scripts = {}
  local in_script = false
  local current_script = ""
  local lines = {}
  
  -- Split text into lines
  for line in text:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  
  -- Look for bash script markers
  for i, line in ipairs(lines) do
    if line:match("^```bash") or line:match("^```shell") then
      in_script = true
      current_script = ""
    elseif in_script and line:match("^```") then
      in_script = false
      if current_script ~= "" then
        table.insert(scripts, current_script)
      end
    elseif in_script then
      current_script = current_script .. line .. "\n"
    end
  end
  
  return scripts
end

-- Extract a single script from Claude's response (legacy function for compatibility)
function M.extract_script(text)
  local scripts = M.extract_scripts(text)
  return scripts[1] or ""
end

-- Save script to temporary file
function M.save_script_to_file(script_text)
  -- Create temporary file
  local temp_file = os.tmpname() -- Get temporary file path
  local script_file = temp_file .. ".sh"
  
  -- Write script to file
  local file = io.open(script_file, "w")
  if not file then
    return nil, "Failed to create temporary script file"
  end
  
  file:write("#!/bin/bash\n\n")
  file:write("# Script generated by TheArchHive Claude\n")
  file:write("# " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
  file:write(script_text)
  file:close()
  
  -- Make script executable
  os.execute("chmod +x " .. script_file)
  
  return script_file
end

-- Save script to user-specified location
function M.save_script_to_user_file(script_text)
  -- Prompt for a file path
  local prompt = "Save script to path: "
  local default_path = os.getenv("HOME") .. "/scripts/claude_script_" .. os.date("%Y%m%d%H%M%S") .. ".sh"
  local file_path = vim.fn.input({
    prompt = prompt,
    default = default_path,
    cancelreturn = "__CANCEL__"
  })
  
  if file_path == "__CANCEL__" or file_path == "" then
    return nil, "Canceled by user"
  end
  
  -- Expand ~ in path
  file_path = file_path:gsub("^~", os.getenv("HOME"))
  
  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(file_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    local ok = vim.fn.mkdir(dir, "p")
    if ok == 0 then
      return nil, "Failed to create directory: " .. dir
    end
  end
  
  -- Write script to file
  local file = io.open(file_path, "w")
  if not file then
    return nil, "Failed to create script file: " .. file_path
  end
  
  file:write("#!/bin/bash\n\n")
  file:write("# Script generated by TheArchHive Claude\n")
  file:write("# " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
  file:write(script_text)
  file:close()
  
  -- Make script executable
  os.execute("chmod +x " .. file_path)
  
  return file_path
end

-- Function to attach to a tmux session
function M.attach_to_tmux_session(session_name)
  -- Create a terminal buffer and run the tmux attach command
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.fn.termopen("tmux attach -t " .. session_name)
  vim.cmd("startinsert")
end

-- Execute script using tmux if available, or fallback to terminal-within-nvim
function M.execute_script(script_file)
  -- Try tmux first if available
  if vim.fn.executable("tmux") == 1 then
    -- Check if we're already in a tmux session
    local in_tmux = os.getenv("TMUX") ~= nil
    
    if in_tmux then
      -- Create a new window in current tmux session
      os.execute(string.format('tmux new-window -n "Claude-Script" "bash %s; echo; echo Press Enter to close...; read"', script_file))
      return true
    else
      -- Start a new tmux session
      os.execute(string.format('tmux new-session -d -s claude-script "bash %s; echo; echo Press Enter to close...; read"', script_file))
      
      -- Show a floating window with instructions
      local info_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(info_buf, 0, -1, false, {
        "Script is running in tmux session 'claude-script'",
        "",
        "Press <Space>ta to attach to this session",
        "or run this command in your terminal:",
        "tmux attach -t claude-script"
      })
      
      local width = 50
      local height = 5
      local row = math.floor((vim.o.lines - height) / 2)
      local col = math.floor((vim.o.columns - width) / 2)
      
      local win = vim.api.nvim_open_win(info_buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded'
      })
      
      -- Add keymap to close the window
      vim.api.nvim_buf_set_keymap(info_buf, 'n', 'q', 
        [[<Cmd>lua vim.api.nvim_win_close(0, true)<CR>]], 
        {noremap = true, silent = true})
      
      -- Add keymap to attach to the tmux session
      vim.api.nvim_buf_set_keymap(info_buf, 'n', '<Space>ta', 
        [[<Cmd>lua require('claude').attach_to_tmux_session('claude-script')<CR>]], 
        {noremap = true, silent = true})
      
      vim.api.nvim_echo({{"Script is running in tmux session 'claude-script'. Press <Space>ta to attach or q to close this message.", "Normal"}}, true, {})
      
      return true
    end
  end
  
  -- Fallback to terminal buffer in Neovim
  local term_buf = vim.api.nvim_create_buf(false, true)
  
  -- Get window dimensions
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  -- Create terminal window
  local term_win = vim.api.nvim_open_win(term_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded'
  })
  
  -- Start terminal with script
  vim.fn.termopen("bash " .. script_file .. "; echo; echo Press Enter to close...; read", {
    on_exit = function()
      if vim.api.nvim_win_is_valid(term_win) then
        vim.api.nvim_win_close(term_win, true)
      end
    end
  })
  
  -- Enter terminal mode automatically
  vim.cmd("startinsert")
  
  return true
end

-- Display script in a preview window
function M.preview_script(script_text)
  -- Create a new buffer for preview
  local preview_buf = vim.api.nvim_create_buf(false, true)
  
  -- Set buffer content
  local lines = {}
  for line in script_text:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(preview_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(preview_buf, 'filetype', 'bash')
  
  -- Get window dimensions
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  -- Create preview window
  local preview_win = vim.api.nvim_open_win(preview_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded'
  })
  
  -- Set window options
  vim.api.nvim_win_set_option(preview_win, 'winblend', 0)
  vim.api.nvim_win_set_option(preview_win, 'cursorline', true)
  
  -- Add title to the window
  vim.api.nvim_buf_set_name(preview_buf, "Script Preview")
  
  -- Return buffer and window IDs
  return preview_buf, preview_win
end

-- Offer script execution to the user
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
  
  -- When pcall succeeds with a function that returns multiple values,
  -- it returns the results directly. No need for another call to init_window.
  local buf, win
  if type(result) == "number" then
    -- If result is a buffer ID
    buf = result
    -- The second return value is the window ID
    -- It should be in the additional return values from pcall
    win = select(2, pcall(init_window))
  else
    -- Error occurred or unexpected return type
    print("Unexpected result from init_window")
    return nil, nil
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
  
  -- Set up keymaps - safer approach
  if buf and win then
    local keymap_ok, keymap_err = pcall(function()
      vim.api.nvim_buf_set_keymap(buf, 'n', '<Space>ca', 
        string.format([[<Cmd>lua require('claude').handle_input(%d, %d)<CR>]], buf, win), 
        {noremap = true, silent = true})
    end)
    
    if not keymap_ok then
      print("Error setting up keymaps: " .. tostring(keymap_err))
    end
  else
    print("Error: Invalid buffer or window")
  end
  
  return buf, win
end

function M.offer_script_execution(buf, response_text)
  -- Extract scripts from the response
  local scripts = M.extract_scripts(response_text)
  
  -- If no scripts found, return
  if #scripts == 0 then
    return
  end
  
  -- Process each script
  for i, script_text in ipairs(scripts) do
    -- Generate a hash for this script for deduplication
    local script_hash = M.simple_hash(script_text)
    
    -- Skip if already processed
    if M.processed_scripts[script_hash] then
      -- This script has already been processed, skip it
      goto continue
    end
    
    -- Mark as processed
    M.processed_scripts[script_hash] = true
    
    -- Create a floating window for options
    local options_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(options_buf, 0, -1, false, {
      "Claude has provided a script. What would you like to do?",
      "",
      "Press 'e' to execute the script",
      "Press 'p' to preview the script",
      "Press 's' to save the script to a file",
      "Press 'q' to dismiss this message"
    })
    
    local width = 50
    local height = 6
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    
    local options_win = vim.api.nvim_open_win(options_buf, true, {
      relative = 'editor',
      width = width,
      height = height,
      row = row,
      col = col,
      style = 'minimal',
      border = 'rounded'
    })
    
    -- Function to cleanup
    local function cleanup()
      if vim.api.nvim_win_is_valid(options_win) then
        vim.api.nvim_win_close(options_win, true)
      end
    end
    
    -- Setup keymaps for actions
    vim.api.nvim_buf_set_keymap(options_buf, 'n', 'e', '', {
      noremap = true,
      callback = function()
        cleanup()
        
        -- Save script to temporary file
        local script_file, err = M.save_script_to_file(script_text)
        if not script_file then
          vim.api.nvim_echo({{"Error saving script: " .. err, "ErrorMsg"}}, true, {})
          return
        end
        
        -- Execute the script
        M.execute_script(script_file)
      end
    })
    
    vim.api.nvim_buf_set_keymap(options_buf, 'n', 'p', '', {
      noremap = true,
      callback = function()
        cleanup()
        
        -- Preview the script
        local preview_buf, preview_win = M.preview_script(script_text)
        
        -- Add keymap to close preview
        vim.api.nvim_buf_set_keymap(preview_buf, 'n', 'q', '', {
          noremap = true,
          callback = function()
            if vim.api.nvim_win_is_valid(preview_win) then
              vim.api.nvim_win_close(preview_win, true)
            end
            
            -- Save script to user file
            local saved_file, err = M.save_script_to_user_file(script_text)
            if not saved_file then
              vim.api.nvim_echo({{"Error saving script: " .. err, "ErrorMsg"}}, true, {})
              return
            end
            
            vim.api.nvim_echo({{"Script saved to: " .. saved_file, "Normal"}}, true, {})
          end
        })
          callback = function()
            if vim.api.nvim_win_is_valid(preview_win) then
              vim.api.nvim_win_close(preview_win, true)
            end
          end
	}
        
        -- Add keymap to execute from preview
        vim.api.nvim_buf_set_keymap(preview_buf, 'n', 'e', '', {
          noremap = true,
          callback = function()
            if vim.api.nvim_win_is_valid(preview_win) then
              vim.api.nvim_win_close(preview_win, true)
            end
            
            -- Save script to temporary file
            local script_file, err = M.save_script_to_file(script_text)
            if not script_file then
              vim.api.nvim_echo({{"Error saving script: " .. err, "ErrorMsg"}}, true, {})
              return
            end
            
            -- Execute the script
            M.execute_script(script_file)
          end
        })
        
        -- Add keymap to save from preview
        vim.api.nvim_buf_set_keymap(preview_buf, 'n', 's', '', {
          noremap = true,
