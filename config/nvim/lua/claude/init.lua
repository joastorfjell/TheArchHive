-- TheArchHive: Claude integration for Neovim
-- This module provides real Claude API integration

local M = {}
local api = vim.api
local fn = vim.fn
local config_module = require('claude.config')
local json = require('json') -- Requires JSON module (can be installed via LuaRocks or plugin)

-- Buffer and window IDs
M.buf = nil
M.win = nil
M.initialized = false
M.history = {}

-- Load Claude configuration
function M.load_config()
  local config_path = config_module.config_path
  local file = io.open(config_path, "r")
  if not file then
    return nil
  end
  
  local content = file:read("*all")
  file:close()
  
  local ok, config = pcall(json.decode, content)
  if not ok then
    print("Error parsing Claude config: " .. config)
    return nil
  end
  
  return config
end

-- Initialize Claude window
function M.init()
  if M.initialized then return end
  
  -- Create buffer
  M.buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(M.buf, 'buftype', 'nofile')
  api.nvim_buf_set_option(M.buf, 'bufhidden', 'hide')
  api.nvim_buf_set_option(M.buf, 'swapfile', false)
  api.nvim_buf_set_name(M.buf, 'TheArchHive-Claude')
  
  -- Initial greeting message
  local lines = {
    "  _____ _           _            _     _   _ _           ",
    " |_   _| |__   ___ / \\   _ __ __| |__ | | | |_|_   _____ ",
    "   | | | '_ \\ / _ \\ \\ | | '__/ _` '_ \\| |_| | \\ \\ / / _ \\",
    "   | | | | | |  __/ _ \\| | | (_| | | | |  _  | |\\ V /  __/",
    "   |_| |_| |_|\\___|_/ \\_\\_|  \\__,_|_| |_|_| |_|_| \\_/ \\___|",
    "",
    "Welcome to Claude integration for TheArchHive!",
    "-----------------------------------------------",
    "",
    "I'm here to help you with your Arch Linux setup and configuration.",
    "Ask me about packages, configurations, or system optimizations.",
    "",
    "Type your question and press <Enter> to send."
  }
  
  api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  
  -- Check if config is available
  local config = M.load_config()
  if not config or not config.api_key then
    api.nvim_buf_set_lines(M.buf, #lines, -1, false, {
      "",
      "⚠️  Claude API is not configured yet!",
      "Run './scripts/setup-claude.sh' to set up your API key."
    })
  end
  
  M.initialized = true
end

-- Open Claude window
function M.open()
  if not M.initialized then
    M.init()
  end
  
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  -- Window options
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded'
  }
  
  -- Create window
  M.win = api.nvim_open_win(M.buf, true, opts)
  
  -- Set window options
  api.nvim_win_set_option(M.win, 'wrap', true)
  api.nvim_win_set_option(M.win, 'cursorline', true)
  
  -- Set key mappings for the Claude buffer
  local function set_mappings()
    local opts = { buffer = M.buf, noremap = true, silent = true }
    
    -- Close window with q
    api.nvim_buf_set_keymap(M.buf, 'n', 'q', ':lua require("claude").close()<CR>', opts)
    
    -- Submit question with <Enter> in normal mode
    api.nvim_buf_set_keymap(M.buf, 'n', '<CR>', ':lua require("claude").ask_question()<CR>', opts)
    
    -- Enter insert mode at the end of the buffer
    api.nvim_command('autocmd BufEnter <buffer=' .. M.buf .. '> startinsert!')
    api.nvim_command('autocmd BufEnter <buffer=' .. M.buf .. '> normal! G')
  end
  
  set_mappings()
  
  -- Add input line
  api.nvim_buf_set_lines(M.buf, -1, -1, false, {"", "> "})
  
  -- Move cursor to input line and enter insert mode
  api.nvim_win_set_cursor(M.win, {api.nvim_buf_line_count(M.buf), 2})
  api.nvim_command('startinsert!')
end

-- Close Claude window
function M.close()
  if M.win and api.nvim_win_is_valid(M.win) then
    api.nvim_win_close(M.win, true)
    M.win = nil
  end
end

-- Call Claude API
function M.call_claude_api(prompt)
  local config = M.load_config()
  if not config or not config.api_key then
    return "Error: Claude API is not configured. Run './scripts/setup-claude.sh' to set up your API key."
  end
  
  -- Add to history
  table.insert(M.history, {role = "user", content = prompt})
  
  -- Create temporary file for the response
  local temp_file = os.tmpname()
  
  -- Prepare message history for the API
  local messages = {}
  -- Only include the last 10 messages to avoid token limits
  local start_idx = math.max(1, #M.history - 10)
  for i = start_idx, #M.history do
    table.insert(messages, M.history[i])
  end
  
  -- Convert to JSON
  local json_data = json.encode({
    model = config.model or "claude-3-5-sonnet-20240620",
    max_tokens = config.max_tokens or 4000,
    temperature = config.temperature or 0.7,
    messages = messages
  })
  
  -- Build curl command
  local cmd = string.format(
    "curl -s -o %s -w '%%{http_code}' -H 'x-api-key: %s' -H 'anthropic-version: 2023-06-01' " ..
    "-H 'content-type: application/json' https://api.anthropic.com/v1/messages -d '%s'",
    temp_file, config.api_key, json_data:gsub("'", "'\\''") -- Escape single quotes
  )
  
  -- Execute curl command
  local http_code = fn.system(cmd)
  
  -- Read response
  local file = io.open(temp_file, "r")
  if not file then
    os.remove(temp_file)
    return "Error: Failed to read API response"
  end
  
  local response_text = file:read("*all")
  file:close()
  os.remove(temp_file)
  
  -- Handle response
  if http_code == "200" then
    local ok, response = pcall(json.decode, response_text)
    if ok and response.content and response.content[1] and response.content[1].text then
      local reply = response.content[1].text
      -- Add to history
      table.insert(M.history, {role = "assistant", content = reply})
      return reply
    else
      return "Error parsing API response: " .. response_text
    end
  else
    return "API Error (HTTP " .. http_code .. "): " .. response_text
  end
end

-- Process user question
function M.ask_question()
  -- Get the last line from the buffer (user input)
  local line_count = api.nvim_buf_line_count(M.buf)
  local last_line = api.nvim_buf_get_lines(M.buf, line_count - 1, line_count, false)[1]
  
  -- Extract the question (remove the prompt symbol)
  local question = last_line:gsub("^> ", ""):gsub("^%s*(.-)%s*$", "%1")
  
  -- Check if question is not empty
  if question == "" then
    return
  end
  
  -- Replace the input line with the question (without the prompt)
  api.nvim_buf_set_lines(M.buf, line_count - 1, line_count, false, {question})
  
  -- Add "Thinking..." message
  api.nvim_buf_set_lines(M.buf, line_count, line_count, false, {"", "Claude is thinking..."})
  
  -- Process in background to avoid blocking UI
  vim.defer_fn(function()
    -- Call Claude API
    local response = M.call_claude_api(question)
    
    -- Remove "Thinking..." message
    api.nvim_buf_set_lines(M.buf, line_count, line_count + 2, false, {})
    
    -- Format and add the response
    local formatted_response = {"", "Claude:"}
    for line in response:gmatch("[^\r\n]+") do
      table.insert(formatted_response, line)
    end
    table.insert(formatted_response, "")
    
    -- Add response to buffer
    api.nvim_buf_set_lines(M.buf, line_count, line_count, false, formatted_response)
    
    -- Add new input line
    api.nvim_buf_set_lines(M.buf, -1, -1, false, {"> "})
    
    -- Move cursor to input line and enter insert mode
    api.nvim_win_set_cursor(M.win, {api.nvim_buf_line_count(M.buf), 2})
    api.nvim_command('startinsert!')
  end, 100)
end

-- Initialize commands
function M.setup()
  -- Create user commands
  vim.cmd [[
    command! ClaudeOpen lua require('claude').open()
    command! ClaudeClose lua require('claude').close()
    command! ClaudeAsk lua require('claude').ask_question()
  ]]
  
  -- Set up key mappings
  vim.api.nvim_set_keymap('n', '<Space>cc', ':ClaudeOpen<CR>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<Space>ca', ':ClaudeAsk<CR>', { noremap = true, silent = true })
end

return M
