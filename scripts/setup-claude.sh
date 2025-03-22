#!/bin/bash

# This script sets up the Claude integration for Neovim

# Create necessary directories
mkdir -p ~/.TheArchHive/snapshots

# Create an initial snapshot if it doesn't exist
if [ ! -f ~/.TheArchHive/latest_snapshot.txt ]; then
    echo "Creating initial system snapshot..."
    
    # Get timestamp
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    SNAPSHOT_FILE=~/.TheArchHive/snapshots/snapshot_$TIMESTAMP.txt
    
    # Create a basic snapshot
    echo "# ArchHive System Snapshot - $TIMESTAMP" > $SNAPSHOT_FILE
    echo "" >> $SNAPSHOT_FILE
    echo "# Basic snapshot - Claude integration setup" >> $SNAPSHOT_FILE
    echo "" >> $SNAPSHOT_FILE
    
    # Try to get some system info if possible
    if command -v uname &> /dev/null; then
        echo "# Kernel" >> $SNAPSHOT_FILE
        uname -r | awk '{print "k:" $1}' >> $SNAPSHOT_FILE
        echo "" >> $SNAPSHOT_FILE
    fi
    
    if [ -f /proc/cpuinfo ]; then
        echo "# CPU" >> $SNAPSHOT_FILE
        grep "model name" /proc/cpuinfo | head -1 | sed 's/model name\s*: //g' | awk '{print "c:" $0}' >> $SNAPSHOT_FILE
        echo "" >> $SNAPSHOT_FILE
    fi
    
    if command -v free &> /dev/null; then
        echo "# Memory" >> $SNAPSHOT_FILE
        free -h | grep Mem | awk '{print "m:" $2}' >> $SNAPSHOT_FILE
    fi
    
    # Copy to latest snapshot location
    cp $SNAPSHOT_FILE ~/.TheArchHive/latest_snapshot.txt
    echo "Basic snapshot created at ~/.TheArchHive/latest_snapshot.txt"
fi

echo "Claude integration setup complete!"
