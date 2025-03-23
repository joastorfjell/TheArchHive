#!/bin/bash
# Simple Claude API test

KEY="CLAUDE-API-KEY"

curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-3-5-sonnet-20240620","messages":[{"role":"user","content":"Hi"}]}'
