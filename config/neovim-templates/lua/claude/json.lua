-- JSON module for Lua
-- This is a minimal JSON encoder/decoder for TheArchHive Claude integration

local json = {}

local escape_char_map = {
  ["\\"] = "\\\\",
  ["\""] = "\\\"",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

local function escape_char(c)
  return escape_char_map[c] or string.format("\\u%04x", c:byte())
end

local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function encode_table(val, stack)
  stack = stack or {}
  
  -- Circular reference check
  if stack[val] then error("circular reference") end
  stack[val] = true
  
  if rawget(val, 1) ~= nil or next(val) == nil then
    -- Treat as array
    local res = {}
    for i, v in ipairs(val) do
      table.insert(res, json.encode(v, stack))
    end
    stack[val] = nil
    return "[" .. table.concat(res, ",") .. "]"
  else
    -- Treat as object
    local res = {}
    for k, v in pairs(val) do
      if type(k) == "string" then
        table.insert(res, encode_string(k) .. ":" .. json.encode(v, stack))
      end
    end
    stack[val] = nil
    return "{" .. table.concat(res, ",") .. "}"
  end
end

function json.encode(val, stack)
  local t = type(val)
  if t == "string" then
    return encode_string(val)
  elseif t == "number" or t == "boolean" or t == "nil" then
    return tostring(val)
  elseif t == "table" then
    return encode_table(val, stack)
  else
    error("unsupported type: " .. t)
  end
end

function json.decode(str)
  if str == "null" then
    return nil
  end
  
  local pos = 1
  local function next_char()
    pos = pos + 1
    return str:sub(pos, pos)
  end
  
  local function skip_whitespace()
    while pos <= #str and str:sub(pos, pos):match("[ \t\n\r]") do
      pos = pos + 1
    end
  end
  
  local function parse_string()
    local has_unicode_escape = false
    local s = ""
    assert(str:sub(pos, pos) == '"', "expected string at position " .. pos)
    pos = pos + 1
    
    while pos <= #str do
      local c = str:sub(pos, pos)
      if c == '"' then
        pos = pos + 1
        return s
      elseif c == '\\' then
        pos = pos + 1
        c = str:sub(pos, pos)
        if c == 'u' then
          pos = pos + 1
          local code = tonumber(str:sub(pos, pos + 3), 16)
          pos = pos + 4
          if code then
            s = s .. string.char(code)
          end
          has_unicode_escape = true
        else
          local replacement = {
            ["\""] = "\"", ["\\"] = "\\", ["/"] = "/",
            ["b"] = "\b", ["f"] = "\f", ["n"] = "\n", ["r"] = "\r", ["t"] = "\t"
          }
          s = s .. (replacement[c] or c)
          pos = pos + 1
        end
      else
        s = s .. c
        pos = pos + 1
      end
    end
    
    error("unterminated string at position " .. pos)
  end
  
  local function parse_number()
    local start = pos
    while pos <= #str and str:sub(pos, pos):match("[-%+%.%d%a]") do
      pos = pos + 1
    end
    local num_str = str:sub(start, pos - 1)
    return tonumber(num_str)
  end
  
  local function parse_array()
    assert(str:sub(pos, pos) == "[", "expected array at position " .. pos)
    pos = pos + 1
    
    local arr = {}
    local i = 1
    
    -- Empty array
    skip_whitespace()
    if str:sub(pos, pos) == "]" then
      pos = pos + 1
      return arr
    end
    
    while pos <= #str do
      skip_whitespace()
      arr[i] = parse_value()
      i = i + 1
      skip_whitespace()
      
      local c = str:sub(pos, pos)
      if c == "]" then
        pos = pos + 1
        return arr
      elseif c == "," then
        pos = pos + 1
      else
        error("expected ',' or ']' at position " .. pos)
      end
    end
    
    error("unterminated array at position " .. pos)
  end
  
  local function parse_object()
    assert(str:sub(pos, pos) == "{", "expected object at position " .. pos)
    pos = pos + 1
    
    local obj = {}
    
    -- Empty object
    skip_whitespace()
    if str:sub(pos, pos) == "}" then
      pos = pos + 1
      return obj
    end
    
    while pos <= #str do
      skip_whitespace()
      
      -- Parse key
      assert(str:sub(pos, pos) == '"', "expected string key at position " .. pos)
      local key = parse_string()
      
      -- Parse colon
      skip_whitespace()
      assert(str:sub(pos, pos) == ":", "expected ':' at position " .. pos)
      pos = pos + 1
      
      -- Parse value
      skip_whitespace()
      obj[key] = parse_value()
      
      skip_whitespace()
      local c = str:sub(pos, pos)
      if c == "}" then
        pos = pos + 1
        return obj
      elseif c == "," then
        pos = pos + 1
      else
        error("expected ',' or '}' at position " .. pos)
      end
    end
    
    error("unterminated object at position " .. pos)
  end
  
  local function parse_value()
    skip_whitespace()
    
    local c = str:sub(pos, pos)
    if c == '"' then
      return parse_string()
    elseif c == '[' then
      return parse_array()
    elseif c == '{' then
      return parse_object()
    elseif c:match("[%-%+%.%d]") then
      return parse_number()
    elseif str:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif str:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    elseif str:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    else
      error("unexpected character at position " .. pos)
    end
  end
  
  skip_whitespace()
  local result = parse_value()
  skip_whitespace()
  
  if pos <= #str then
    error("trailing garbage at position " .. pos)
  end
  
  return result
end

return json
