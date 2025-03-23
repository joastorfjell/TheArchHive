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

-- Function to execute the script from preview window
function M.execute_script_from_preview()
  if not M.current_script_text then
    vim.api.nvim_echo({{"No script available", "ErrorMsg"}}, true, {})
    return
  end
  
  local script_file, err = M.save_script_to_file(M.current_script_text)
  if not script_file then
    vim.api.nvim_echo({{err, "ErrorMsg"}}, true, {})
    return
  end
  
  M.execute_script(script_file)
end

-- Function to validate script from preview window
function M.validate_script_from_preview()
  if not M.current_script_text then
    vim.api.nvim_echo({{"No script available", "ErrorMsg"}}, true, {})
    return
  end
  
  local validation, err = M.validate_script(M.current_script_text)
  if not validation then
    vim.api.nvim_echo({{err, "ErrorMsg"}}, true, {})
    return
  end
  
  M.execute_validated_script(validation.script_path, validation.validation_id)
end

-- Function to save the script to a user-specified file
function M.save_script_from_preview()
  if not M.current_script_text then
    vim.api.nvim_echo({{"No script available", "ErrorMsg"}}, true, {})
    return
  end
  
  -- Ask for file path
  local file_path = vim.fn.input("Save script to file: ", vim.fn.expand("~/"), "file")
  
  if file_path == "" then
    return
  end
  
  -- Expand path
  file_path = vim.fn.expand(file_path)
  
  -- Write to file
  local file = io.open(file_path, "w")
  if not file then
    vim.api.nvim_echo({{"Failed to open file for writing: " .. file_path, "ErrorMsg"}}, true, {})
    return
  end
  
  file:write("#!/bin/bash\n\n")
  file:write("# Script generated by TheArchHive Claude\n")
  file:write("# " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
  file:write(M.current_script_text)
  file:close()
  
  -- Make executable
  os.execute("chmod +x " .. file_path)
  
  vim.api.nvim_echo({{"Script saved to " .. file_path, "Normal"}}, true, {})
end

-- Extract script from Claude's response
function M.extract_script(text)
  local script_text = ""
  local in_script = false
  local lines = {}
  
  -- Split text into lines
  for line in text:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  
  -- Look for bash script markers
  for i, line in ipairs(lines) do
    if line:match("^```bash") or line:match("^```shell") then
      in_script = true
    elseif in_script and line:match("^```") then
      in_script = false
    elseif in_script then
      script_text = script_text .. line .. "\n"
    end
  end
  
  return script_text
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
      vim.api.nvim_echo({{"Script is running in tmux session 'claude-script'. Use 'tmux attach -t claude-script' to view it.", "Normal"}}, true, {})
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

-- Function to validate a script
function M.validate_script(script_text, validation_level)
  local conf = M.config or init_config()
  validation_level = validation_level or "normal"
  
  -- Send to MCP server for validation
  local response, err = make_http_request(
    conf.mcp_url .. "/script/validate", 
    "POST", 
    {
      body = json.encode({
        script = script_text,
        validation_level = validation_level
      })
    }
  )
  
  if err or not response or response.status ~= 200 then
    return nil, "Failed to validate script: " .. (err or (response and response.body or "Unknown error"))
  end
  
  local ok, parsed_body = pcall(json.decode, response.body)
  if not ok then
    return nil, "Failed to parse validation response: " .. tostring(parsed_body)
  end
  
  return parsed_body, nil
end

-- Function to execute a validated script
function M.execute_validated_script(script_file, validation_id)
  -- Try tmux first if available
  if vim.fn.executable("tmux") == 1 then
    -- Check if we're already in a tmux session
    local in_tmux = os.getenv("TMUX") ~= nil
    
    if in_tmux then
      -- Create a new window in current tmux session
      os.execute(string.format('tmux new-window -n "Claude-Script" "bash %s; echo; echo Press Enter to close...; read"', script_file))
      
      -- Start a background job to poll validation results
      vim.defer_fn(function()
        M.poll_validation_results(validation_id)
      end, 1000)
      
      return true
    else
      -- Start a new tmux session
      os.execute(string.format('tmux new-session -d -s claude-script "bash %s; echo; echo Press Enter to close...; read"', script_file))
      vim.api.nvim_echo({{"Script is running in tmux session 'claude-script'. Use 'tmux attach -t claude-script' to view it.", "Normal"}}, true, {})
      
      -- Start a background job to poll validation results
      vim.defer_fn(function()
        M.poll_validation_results(validation_id)
      end, 1000)
      
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
  
  -- Start a background job to poll validation results
  vim.defer_fn(function()
    M.poll_validation_results(validation_id)
  end, 1000)
  
  -- Enter terminal mode automatically
  vim.cmd("startinsert")
  
  return true
end

-- Function to fetch validation results
function M.fetch_validation_results(validation_id)
  local conf = M.config or init_config()
  
  local response, err = make_http_request(
    conf.mcp_url .. "/script/results/" .. validation_id, 
    "GET"
  )
  
  if err or not response or response.status ~= 200 then
    return nil, "Failed to fetch validation results: " .. (err or (response and response.body or "Unknown error"))
  end
  
  local ok, parsed_body = pcall(json.decode, response.body)
  if not ok then
    return nil, "Failed to parse validation results: " .. tostring(parsed_body)
  end
  
  return parsed_body, nil
end

-- Poll validation results periodically
function M.poll_validation_results(validation_id)
  local interval = 2000  -- Check every 2 seconds
  local max_attempts = 30  -- Try for up to 1 minute
  local attempts = 0
  
  local function check_results()
    attempts = attempts + 1
    
    if attempts > max_attempts then
      -- Stop polling after max attempts
      vim.api.nvim_echo({{"Validation timed out after " .. max_attempts * interval / 1000 .. " seconds", "WarningMsg"}}, true, {})
      return
    end
    
    local results, err = M.fetch_validation_results(validation_id)
    
    if err then
      -- Error fetching results
      vim.defer_fn(check_results, interval)
      return
    end
    
    if results.status == "completed" then
      -- Process completed validation
      M.process_validation_results(results)
    else
      -- Not done yet, keep polling
      vim.defer_fn(check_results, interval)
    end
  end
  
  -- Start polling
  vim.defer_fn(check_results, interval)
end

-- Process and display validation results
function M.process_validation_results(results)
  -- Create a new buffer for results
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  -- Prepare lines to display
  local lines = {
    "# Script Validation Results",
    "",
    "Validation ID: " .. results.validation_id,
    "Status: " .. results.status,
    "Start time: " .. results.start_time,
    "End time: " .. (results.end_time or "N/A"),
    "",
    "## Execution Steps:",
    ""
  }
  
  local has_errors = false
  
  -- Add each step
  for _, step in ipairs(results.steps) do
    table.insert(lines, "### Step " .. step.step .. ": `" .. step.command .. "`")
    table.insert(lines, "Exit code: " .. step.exit_code)
    if step.exit_code ~= 0 then
      has_errors = true
      table.insert(lines, "**ERROR: Command failed**")
    end
    table.insert(lines, "")
    table.insert(lines, "```")
    
    -- Split output by lines
    for output_line in step.output:gmatch("[^\r\n]+") do
      table.insert(lines, output_line)
    end
    
    table.insert(lines, "```")
    table.insert(lines, "")
  end
  
  -- Summary
  if has_errors then
    table.insert(lines, "## Summary: Script had errors during execution")
  else
    table.insert(lines, "## Summary: Script executed successfully")
  end
  
  -- Set buffer content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  -- Create window
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded'
  })
  
  -- Store validation results to send back to Claude if needed
  M.last_validation_results = results
  
  -- Add keybinding to send results to Claude
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Space>cv', 
    [[<Cmd>lua require('claude').send_validation_to_claude()<CR>]], 
    {noremap = true, silent = true})
  
  vim.api.nvim_echo({{"Press <Space>cv to send these validation results to Claude for analysis", "Normal"}}, true, {})
end

-- Function to send validation results to Claude
function M.send_validation_to_claude()
  if not M.last_validation_results then
    vim.api.nvim_echo({{"No validation results available", "ErrorMsg"}}, true, {})
    return
  end
  
  -- Create a summary of the validation results to send to Claude
  local summary = "Here are the results of the script execution:\n\n"
  
  -- Add basic info
  summary = summary .. "Script execution " .. 
    (M.last_validation_results.status == "completed" and "completed" or "did not complete") .. 
    ".\n\n"
  
  -- Add step details
  local failed_steps = {}
  for _, step in ipairs(M.last_validation_results.steps) do
    if step.exit_code ~= 0 then
      table.insert(failed_steps, {
        step = step.step,
        command = step.command,
        output = step.output
      })
    end
  end
  
  if #failed_steps > 0 then
    summary = summary .. "The following steps failed:\n\n"
    
    for _, fail in ipairs(failed_steps) do
      summary = summary .. "Step " .. fail.step .. ": " .. fail.command .. "\n"
      summary = summary .. "Error output: " .. fail.output .. "\n\n"
    end
    
    summary = summary .. "Please help me fix these issues and provide an updated script."
  else
    summary = summary .. "All steps completed successfully."
  end
  
  -- Send to Claude
  local buf, win = M.init()
  M.handle_input(buf, win, summary)
end

-- Function to offer script execution from Claude response
function M.offer_script_execution(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local full_text = table.concat(lines, "\n")
  
  -- Extract script from response
  local script_text = M.extract_script(full_text)
  
  if script_text == "" then
    -- No script found
    return
  end
  
  -- Ask user if they want to execute the script
  local choice = vim.fn.confirm("Claude provided a script. Do you want to execute it?", "&Yes\n&Validate\n&View Script\n&No", 2)
  
  if choice == 1 then
    -- Execute script without validation
    local script_file, err = M.save_script_to_file(script_text)
    if not script_file then
      vim.api.nvim_echo({{err, "ErrorMsg"}}, true, {})
      return
    end
    
    M.execute_script(script_file)
  elseif choice == 2 then
    -- Execute with validation
    local validation, err = M.validate_script(script_text)
    if not validation then
      vim.api.nvim_echo({{err, "ErrorMsg"}}, true, {})
      return
    end
    
    M.execute_validated_script(validation.script_path, validation.validation_id)
  elseif choice == 3 then
    -- View script
    local script_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(script_buf, 0, -1, false, vim.split(script_text, "\n"))
    vim.api.nvim_buf_set_option(script_buf, 'filetype', 'bash')
    vim.api.nvim_buf_set_name(script_buf, "Claude-Script-Preview")
    
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    
    local win = vim.api.nvim_open_win(script_buf, true, {
      relative = 'editor',
      width = width,
      height = height,
      row = row,
      col = col,
      style = 'minimal',
      border = 'rounded'
    })
    
    -- Add keymap to execute from preview window
    vim.api.nvim_buf_set_keymap(script_buf, 'n', '<Space>cr', 
      string.format([[<Cmd>lua require('claude').execute_script_from_preview()<CR>]]), 
      {noremap = true, silent = true})
    
    -- Add keymap to validate script from preview window
    vim.api.nvim_buf_set_keymap(script_buf, 'n', '<Space>cv', 
      string.format([[<Cmd>lua require('claude').validate_script_from_preview()<CR>]]), 
      {noremap = true, silent = true})
    
    -- Add keymap to save script to file
    vim.api.nvim_buf_set_keymap(script_buf, 'n', '<Space>cs', 
      string.format([[<Cmd>lua require('claude').save_script_from_preview()<CR>]]), 
      {noremap = true, silent = true})
    
    -- Store script text for later use
    M.current_script_text = script_text
    
    vim.api.nvim_echo({{"Press <Space>cr to run, <Space>cv to validate, <Space>cs to save, or q to close", "Normal"}}, true, {})
