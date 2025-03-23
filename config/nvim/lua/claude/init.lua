-- TheArchHive: Claude integration for Neovim
-- Fixed version with proper API request format including max_tokens

local M = {}
local api = vim.api
local fn = vim.fn

-- Buffer and window IDs
M.buf = nil
M.win = nil
M.initialized = false
M.history = {}

-- Load configuration - simplified for reliability
local function load_config()
    local home = os.getenv("HOME")
    local config_path = home .. "/.config/thearchhive/claude_config.json"
    
    local file = io.open(config_path, "r")
    if not file then
        return nil
    end
    
    local content = file:read("*all")
    file:close()
    
    -- Simple pattern matching to extract API key
    local api_key = content:match('"api_key"%s*:%s*"([^"]+)"')
    if not api_key then
        return nil
    end
    
    return {
        api_key = api_key,
        model = content:match('"model"%s*:%s*"([^"]+)"') or "claude-3-5-sonnet-20240620",
        max_tokens = 4000,
        temperature = 0.7
    }
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
        "+--------------------------------------+",
        "|             TheArchHive             |",
        "|      Claude AI Integration          |",
        "+--------------------------------------+",
        "",
        "Welcome to TheArchHive Claude Integration!",
        "----------------------------------------",
        "",
        "I'm here to help you with your Arch Linux setup and configuration.",
        "Ask me about packages, configurations, or system optimizations.",
        "",
    }
    
    -- Check if config is available
    local config = load_config()
    if not config or not config.api_key then
        table.insert(lines, "⚠️  Claude API is not configured yet!")
        table.insert(lines, "Run './scripts/setup-claude.sh' to set up your API key.")
    else
        table.insert(lines, "Claude API is configured and ready to use.")
        table.insert(lines, "Type your question and press <Enter> to send.")
    end
    
    -- Set buffer lines
    api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
    
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
    
    -- Set key mappings
    api.nvim_buf_set_keymap(M.buf, 'n', 'q', ':lua require("claude").close()<CR>', 
                          {noremap = true, silent = true})
    api.nvim_buf_set_keymap(M.buf, 'n', '<CR>', ':lua require("claude").ask_question()<CR>', 
                          {noremap = true, silent = true})
    
    -- Add input line if not already present
    local line_count = api.nvim_buf_line_count(M.buf)
    local last_line = api.nvim_buf_get_lines(M.buf, line_count - 1, line_count, false)[1] or ""
    
    if last_line ~= "> " then
        api.nvim_buf_set_lines(M.buf, line_count, line_count, false, {"", "> "})
    end
    
    -- Move cursor to input line and enter insert mode
    local new_line_count = api.nvim_buf_line_count(M.buf)
    api.nvim_win_set_cursor(M.win, {new_line_count, 2})
    vim.cmd('startinsert!')
end

-- Close Claude window
function M.close()
    if M.win and api.nvim_win_is_valid(M.win) then
        api.nvim_win_close(M.win, true)
    end
    M.win = nil
end

-- Call Claude API
function M.call_claude_api(prompt)
    local config = load_config()
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
    
    -- Convert messages to JSON format manually
    local messages_json = "["
    for i, msg in ipairs(messages) do
        if i > 1 then messages_json = messages_json .. "," end
        messages_json = messages_json .. '{"role":"' .. msg.role .. '","content":"' 
                      .. msg.content:gsub('"', '\\"'):gsub('\n', '\\n') .. '"}'
    end
    messages_json = messages_json .. "]"
    
    -- Build JSON data with max_tokens parameter included
    local json_data = '{"model":"' .. config.model 
                    .. '","max_tokens":' .. config.max_tokens
                    .. ',"temperature":' .. config.temperature
                    .. ',"messages":' .. messages_json .. '}'
    
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
        -- Extract the text content using pattern matching
        local text = response_text:match('"text":"([^"]*)"')
        if text then
            -- Unescape the text
            text = text:gsub('\\"', '"'):gsub('\\\\', '\\'):gsub('\\n', '\n')
            -- Add to history
            table.insert(M.history, {role = "assistant", content = text})
            return text
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
    local last_line = api.nvim_buf_get_lines(M.buf, line_count - 1, line_count, false)[1] or ""
    
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
        
        -- Get current line count (it might have changed)
        local current_line_count = api.nvim_buf_line_count(M.buf)
        
        -- Find the "Thinking..." line
        local thinking_line = -1
        for i = 0, current_line_count - 1 do
            local line = api.nvim_buf_get_lines(M.buf, i, i + 1, false)[1] or ""
            if line == "Claude is thinking..." then
                thinking_line = i
                break
            end
        end
        
        -- Remove "Thinking..." message if found
        if thinking_line >= 0 then
            api.nvim_buf_set_lines(M.buf, thinking_line - 1, thinking_line + 1, false, {})
        end
        
        -- Format and add the response
        local formatted_response = {"", "Claude:"}
        for line in response:gmatch("[^\r\n]+") do
            table.insert(formatted_response, line)
        end
        table.insert(formatted_response, "")
        
        -- Add response to buffer
        api.nvim_buf_set_lines(M.buf, current_line_count, current_line_count, false, formatted_response)
        
        -- Add new input line
        api.nvim_buf_set_lines(M.buf, -1, -1, false, {"> "})
        
        -- Move cursor to input line and enter insert mode
        if M.win and api.nvim_win_is_valid(M.win) then
            local new_line_count = api.nvim_buf_line_count(M.buf)
            api.nvim_win_set_cursor(M.win, {new_line_count, 2})
            vim.cmd('startinsert!')
        end
    end, 100)
end

-- Initialize commands
function M.setup()
    vim.cmd [[
        command! ClaudeOpen lua require('claude').open()
        command! ClaudeClose lua require('claude').close()
        command! ClaudeAsk lua require('claude').ask_question()
    ]]
    
    vim.api.nvim_set_keymap('n', '<Space>cc', ':ClaudeOpen<CR>', 
                          {noremap = true, silent = true})
    vim.api.nvim_set_keymap('n', '<Space>ca', ':ClaudeAsk<CR>', 
                          {noremap = true, silent = true})
end

return M
