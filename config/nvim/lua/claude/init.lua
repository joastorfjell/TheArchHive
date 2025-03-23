-- TheArchHive: Claude integration for Neovim
-- Fixed version that handles buffer and keymap errors

local M = {}
local api = vim.api
local fn = vim.fn

-- Buffer and window IDs
M.buf = nil
M.win = nil
M.initialized = false
M.history = {}

-- Safe require function to handle missing modules
local function safe_require(module)
    local ok, result = pcall(require, module)
    if not ok then
        print("Error loading module " .. module .. ": " .. result)
        return nil
    end
    return result
end

-- Load configuration
local function load_config()
    local config_module = safe_require('claude.config')
    if not config_module then
        return {
            config_path = nil,
            api_configured = false
        }
    end
    
    -- Try to load the config file
    if config_module.config_path then
        local file = io.open(config_module.config_path, "r")
        if file then
            local content = file:read("*all")
            file:close()
            
            local json = safe_require('json')
            if json then
                local ok, config = pcall(json.decode, content)
                if ok then
                    return config
                end
            end
        end
    end
    
    return nil
end

-- Initialize Claude window
function M.init()
    if M.initialized then return end
    
    -- Create buffer
    M.buf = api.nvim_create_buf(false, true)
    
    -- Safety check
    if not M.buf or M.buf == 0 then
        print("Error: Failed to create Claude buffer")
        return
    end
    
    -- Set buffer options safely
    local function set_buf_option(name, value)
        pcall(api.nvim_buf_set_option, M.buf, name, value)
    end
    
    set_buf_option('buftype', 'nofile')
    set_buf_option('bufhidden', 'hide')
    set_buf_option('swapfile', false)
    pcall(api.nvim_buf_set_name, M.buf, 'TheArchHive-Claude')
    
    -- Initial greeting message
    local lines = {
        "  _____ _           _            _     _   _ _           ",
        " |_   _| |__   ___ / \\\\   _ __ __| |__ | | | |_|_   _____ ",
        "   | | | '_ \\\\ / _ \\\\ \\\\ | | '__/ _` '_ \\\\| |_| | \\\\ \\\\ / / _ \\\\",
        "   | | | | | |  __/ _ \\\\| | | (_| | | | |  _  | |\\\\  V /  __/",
        "   |_| |_| |_|\\\\___|_/ \\\\_\\\\_|  \\\\__,_|_| |_|_| |_|_| \\\\_/ \\\\___|",
        "",
        "Welcome to TheArchHive Claude Integration!",
        "----------------------------------------",
        "",
        "I'm here to help you with your Arch Linux setup and configuration.",
        "Ask me about packages, configurations, or system optimizations.",
        "",
    }
    
    -- Safely set buffer lines
    pcall(api.nvim_buf_set_lines, M.buf, 0, -1, false, lines)
    
    -- Check if config is available
    local config = load_config()
    if not config or not config.api_key then
        table.insert(lines, "⚠️  Claude API is not configured yet!")
        table.insert(lines, "Run './scripts/setup-claude.sh' to set up your API key.")
    else
        table.insert(lines, "Claude API is configured and ready to use.")
        table.insert(lines, "Type your question and press <Enter> to send.")
    end
    
    -- Update buffer with additional lines
    pcall(api.nvim_buf_set_lines, M.buf, 0, -1, false, lines)
    
    M.initialized = true
end

-- Open Claude window
function M.open()
    if not M.initialized then
        M.init()
    end
    
    -- Safety check
    if not M.buf or not api.nvim_buf_is_valid(M.buf) then
        print("Error: Claude buffer is not valid")
        M.initialized = false
        M.init()
        if not M.initialized then
            return
        end
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
    
    -- Create window safely
    local ok, win = pcall(api.nvim_open_win, M.buf, true, opts)
    if not ok or not win then
        print("Error opening Claude window: " .. (win or "unknown error"))
        return
    end
    
    M.win = win
    
    -- Set window options safely
    pcall(api.nvim_win_set_option, M.win, 'wrap', true)
    pcall(api.nvim_win_set_option, M.win, 'cursorline', true)
    
    -- Set key mappings safely
    local function safe_keymap(mode, lhs, rhs, opts)
        pcall(api.nvim_buf_set_keymap, M.buf, mode, lhs, rhs, opts or {})
    end
    
    -- Close window with q
    safe_keymap('n', 'q', ':lua require("claude").close()<CR>', 
                {noremap = true, silent = true})
    
    -- Submit question with <Enter> in normal mode
    safe_keymap('n', '<CR>', ':lua require("claude").ask_question()<CR>', 
                {noremap = true, silent = true})
    
    -- Add input line if not already present
    local line_count = api.nvim_buf_line_count(M.buf)
    local last_line = api.nvim_buf_get_lines(M.buf, line_count - 1, line_count, false)[1] or ""
    
    if last_line ~= "> " then
        pcall(api.nvim_buf_set_lines, M.buf, line_count, line_count, false, {"", "> "})
    end
    
    -- Try to move cursor to input line and enter insert mode
    pcall(function()
        local new_line_count = api.nvim_buf_line_count(M.buf)
        api.nvim_win_set_cursor(M.win, {new_line_count, 2})
        vim.cmd('startinsert!')
    end)
end

-- Close Claude window
function M.close()
    if M.win and api.nvim_win_is_valid(M.win) then
        pcall(api.nvim_win_close, M.win, true)
    end
    M.win = nil
end

-- Call Claude API
function M.call_claude_api(prompt)
    local json = safe_require('json')
    if not json then
        return "Error: JSON module not found. Please check your installation."
    end
    
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
    -- Safety check
    if not M.buf or not api.nvim_buf_is_valid(M.buf) then
        print("Error: Claude buffer is not valid")
        return
    end
    
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
    pcall(api.nvim_buf_set_lines, M.buf, line_count - 1, line_count, false, {question})
    
    -- Add "Thinking..." message
    pcall(api.nvim_buf_set_lines, M.buf, line_count, line_count, false, {"", "Claude is thinking..."})
    
    -- Process in background to avoid blocking UI
    vim.defer_fn(function()
        -- Call Claude API
        local response = M.call_claude_api(question)
        
        -- Safety check
        if not M.buf or not api.nvim_buf_is_valid(M.buf) then
            print("Error: Claude buffer was closed during API call")
            return
        end
        
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
            pcall(api.nvim_buf_set_lines, M.buf, thinking_line - 1, thinking_line + 1, false, {})
        end
        
        -- Format and add the response
        local formatted_response = {"", "Claude:"}
        for line in response:gmatch("[^\r\n]+") do
            table.insert(formatted_response, line)
        end
        table.insert(formatted_response, "")
        
        -- Add response to buffer
        pcall(api.nvim_buf_set_lines, M.buf, current_line_count, current_line_count, false, formatted_response)
        
        -- Add new input line
        pcall(api.nvim_buf_set_lines, M.buf, -1, -1, false, {"> "})
        
        -- Move cursor to input line and enter insert mode
        if M.win and api.nvim_win_is_valid(M.win) then
            pcall(function()
                local new_line_count = api.nvim_buf_line_count(M.buf)
                api.nvim_win_set_cursor(M.win, {new_line_count, 2})
                vim.cmd('startinsert!')
            end)
        end
    end, 100)
end

-- Initialize commands
function M.setup()
    -- Create user commands safely
    pcall(vim.cmd, [[
        command! ClaudeOpen lua require('claude').open()
        command! ClaudeClose lua require('claude').close()
        command! ClaudeAsk lua require('claude').ask_question()
    ]])
    
    -- Set up key mappings safely
    pcall(vim.api.nvim_set_keymap, 'n', '<Space>cc', ':ClaudeOpen<CR>', 
          {noremap = true, silent = true})
    pcall(vim.api.nvim_set_keymap, 'n', '<Space>ca', ':ClaudeAsk<CR>', 
          {noremap = true, silent = true})
end

return M
