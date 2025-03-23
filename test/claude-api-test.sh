#!/bin/bash
# TheArchHive - Claude API Test Script
# This script tests the Claude API with a simple query

# Configuration
API_KEY_FILE="$HOME/.config/thearchhive/claude_config.json"

# Check if API key file exists
if [ ! -f "$API_KEY_FILE" ]; then
  echo "Error: API key file not found at $API_KEY_FILE"
  echo "Please run './scripts/setup-claude.sh' first"
  exit 1
fi

# Extract API key from config file
API_KEY=$(grep -o '"api_key": "[^"]*"' "$API_KEY_FILE" | cut -d'"' -f4)

if [ -z "$API_KEY" ]; then
  echo "Error: Could not extract API key from $API_KEY_FILE"
  exit 1
fi

echo "Testing Claude API..."
echo "Using API key: ${API_KEY:0:4}...${API_KEY: -4}"

# Create request payload with max_tokens parameter included
REQUEST='{
  "model": "claude-3-5-sonnet-20240620",
  "max_tokens": 100,
  "messages": [{"role": "user", "content": "Say hello to TheArchHive"}]
}'

# Make API request
RESPONSE=$(curl -s -w "\nHTTP Status: %{http_code}" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  https://api.anthropic.com/v1/messages \
  -d "$REQUEST")

# Extract HTTP status code
HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP Status:" | cut -d' ' -f3)

# Extract response content
RESPONSE_CONTENT=$(echo "$RESPONSE" | sed '$d')

# Check if request was successful
if [ "$HTTP_STATUS" = "200" ]; then
  echo "API test successful!"
  echo -e "\nResponse Preview:"
  # Extract just the text content for preview
  TEXT=$(echo "$RESPONSE_CONTENT" | grep -o '"text":"[^"]*"' | cut -d'"' -f4)
  echo "$TEXT"
else
  echo "API test failed with HTTP status: $HTTP_STATUS"
  echo -e "\nError details:"
  echo "$RESPONSE_CONTENT"
fi
