#!/bin/bash
# Run ./start.sh

# Set environment variables for the session
source .env.example

# Start Phoenix server
iex -S mix phx.server
