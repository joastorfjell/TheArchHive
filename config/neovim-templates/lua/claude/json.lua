-- Simple JSON parser for Claude integration
local json = {}

-- Forward declarations for recursive functions
local parse_value
local parse_object
local parse_array
local parse_string
local parse_number

-- Helper function to skip whitespace
local function skip_whitespace(str, pos)
  while pos <= #str and string.match(string.sub(str, pos, pos), "^[ \n\r\t]") do
    pos = pos + 1
  end
  return pos
end

-- Parse a JSON value
parse_value = function(str, pos)
  pos = skip_whitespace(str, pos)
  
  local char = string.sub(str, pos, pos)
  
  if char == "{" then
    return parse_object(str, pos)
  elseif char == "[" then
    return parse_array(str, pos)
  elseif char == "\"" then
    return parse_string(str, pos)
  elseif string.match(char, "^[%d%-]") then
    return parse_number(str, pos)
  elseif string.sub(str, pos, pos + 3) == "true" then
    return true, pos + 4
  elseif string.sub(str, pos, pos + 4) == "false" then
    return false, pos + 5
  elseif string.sub(str, pos, pos + 3) == "null" then
    return nil, pos + 4
  else
    error("Unexpected character at position " .. pos .. ": " .. char)
  end
end

-- Parse a JSON object
parse_object = function(str, pos)
  local obj = {}
  pos = pos + 1  -- Skip the opening brace
  
  -- Check for empty object
  pos = skip_whitespace(str, pos)
  if string.sub(str, pos, pos) == "}" then
    return obj, pos + 1
  end
  
  while true do
    -- Parse key
    pos = skip_whitespace(str, pos)
    if string.sub(str, pos, pos) ~= "\"" then
      error("Expected string key at position " .. pos)
    end
    
    local key, next_pos = parse_string(str, pos)
    pos = next_pos
    
    -- Parse colon
    pos = skip_whitespace(str, pos)
    if string.sub(str, pos, pos) ~= ":" then
      error("Expected ':' at position " .. pos)
    end
    pos = pos + 1
    
    -- Parse value
    local val
    val, pos = parse_value(str, pos)
    obj[key] = val
    
    -- Check for end of object or next property
    pos = skip_whitespace(str, pos)
    local char = string.sub(str, pos, pos)
    
    if char == "}" then
      return obj, pos + 1
    elseif char == "," then
      pos = pos + 1
    else
      error("Expected ',' or '}' at position " .. pos)
    end
  end
end

-- Parse a JSON array
parse_array = function(str, pos)
  local arr = {}
  pos = pos + 1  -- Skip the opening bracket
  
  -- Check for empty array
  pos = skip_whitespace(str, pos)
  if string.sub(str, pos, pos) == "]" then
    return arr, pos + 1
  end
  
  while true do
    -- Parse value
    local val
    val, pos = parse_value(str, pos)
    table.insert(arr, val)
    
    -- Check for end of array or next element
    pos = skip_whitespace(str, pos)
    local char = string.sub(str, pos, pos)
    
    if char == "]" then
      return arr, pos + 1
    elseif char == "," then
      pos = pos + 1
    else
      error("Expected ',' or ']' at position " .. pos)
    end
  end
end

-- Parse a JSON string
parse_string = function(str, pos)
  pos = pos + 1  -- Skip the opening quote
  local start_pos = pos
  local escaped = false
  
  while pos <= #str do
    local char = string.sub(str, pos, pos)
    
    if escaped then
      -- Handle escape sequences
      escaped = false
    elseif char == "\\" then
      escaped = true
    elseif char == "\"" then
      -- Found the closing quote
      local content = string.sub(str, start_pos, pos - 1)
      -- Handle basic escape sequences
      content = content:gsub("\\\"", "\"")
      content = content:gsub("\\\\", "\\")
      content = content:gsub("\\n", "\n")
      content = content:gsub("\\r", "\r")
      content = content:gsub("\\t", "\t")
      return content, pos + 1
    end
    
    pos = pos + 1
  end
  
  error("Unterminated string starting at position " .. (start_pos - 1))
end

-- Parse a JSON number
parse_number = function(str, pos)
  local start_pos = pos
  
  -- Skip sign
  if string.sub(str, pos, pos) == "-" then
    pos = pos + 1
  end
  
  -- Parse integer part
  while pos <= #str and string.match(string.sub(str, pos, pos), "%d") do
    pos = pos + 1
  end
  
  -- Parse decimal part
  if pos <= #str and string.sub(str, pos, pos) == "." then
    pos = pos + 1
    while pos <= #str and string.match(string.sub(str, pos, pos), "%d") do
      pos = pos + 1
    end
  end
  
  -- Parse exponent
  if pos <= #str and string.match(string.sub(str, pos, pos), "[eE]") then
    pos = pos + 1
    -- Skip sign
    if pos <= #str and string.match(string.sub(str, pos, pos), "[%+%-]") then
      pos = pos + 1
    end
    -- Parse exponent value
    while pos <= #str and string.match(string.sub(str, pos, pos), "%d") do
      pos = pos + 1
    end
  end
  
  local num_str = string.sub(str, start_pos, pos - 1)
  return tonumber(num_str), pos
end

-- Public function to decode JSON
function json.decode(str)
  if str == nil or str == "" then
    return nil
  end
  
  local success, result = pcall(function()
    local pos = 1
    local value, _ = parse_value(str, pos)
    return value
  end)
  
  if success then
    return result
  else
    error("JSON decode error: " .. result)
    return nil
  end
end

-- Public function to encode JSON
function json.encode(data)
  if data == nil then
    return "null"
  elseif type(data) == "boolean" then
    return data and "true" or "false"
  elseif type(data) == "number" then
    return tostring(data)
  elseif type(data) == "string" then
    -- Escape special characters
    local escaped = data:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return "\"" .. escaped .. "\""
  elseif type(data) == "table" then
    -- Check if the table is an array
    local is_array = true
    local max_index = 0
    
    for k, _ in pairs(data) do
      if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
        is_array = false
        break
      end
      max_index = math.max(max_index, k)
    end
    
    if is_array and max_index > 0 then
      -- Encode as array
      local elements = {}
      for i = 1, max_index do
        table.insert(elements, json.encode(data[i] ~= nil and data[i] or vim.NIL))
      end
      return "[" .. table.concat(elements, ",") .. "]"
    else
      -- Encode as object
      local elements = {}
      for k, v in pairs(data) do
        if type(k) == "string" or type(k) == "number" then
          table.insert(elements, json.encode(tostring(k)) .. ":" .. json.encode(v))
        end
      end
      return "{" .. table.concat(elements, ",") .. "}"
    end
  else
    error("Cannot encode value of type " .. type(data))
    return nil
  end
end

return json
