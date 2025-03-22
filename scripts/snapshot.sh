#!/bin/bash

# Create directory for snapshots
mkdir -p ~/.TheArchHive/snapshots

# Get timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SNAPSHOT_FILE=~/.TheArchHive/snapshots/snapshot_$TIMESTAMP.txt

# Begin snapshot
echo "# TheArchHive System Snapshot - $TIMESTAMP" > $SNAPSHOT_FILE
echo "" >> $SNAPSHOT_FILE

# Get Neovim version
NEOVIM_VERSION=$(pacman -Q neovim 2>/dev/null | awk '{print $2}')
if [ ! -z "$NEOVIM_VERSION" ]; then
  echo "p:neovim-$NEOVIM_VERSION" >> $SNAPSHOT_FILE
fi

# Get other key packages
echo "# Core packages" >> $SNAPSHOT_FILE
pacman -Q git python bash 2>/dev/null | awk '{print "p:" $1 "-" $2}' >> $SNAPSHOT_FILE

# Get kernel info
echo "" >> $SNAPSHOT_FILE
echo "# Kernel" >> $SNAPSHOT_FILE
uname -r | awk '{print "k:" $1}' >> $SNAPSHOT_FILE

# Get CPU info
echo "" >> $SNAPSHOT_FILE
echo "# CPU" >> $SNAPSHOT_FILE
grep "model name" /proc/cpuinfo | head -1 | sed 's/model name\s*: //g' | awk '{print "c:" $0}' >> $SNAPSHOT_FILE

# Get memory info
echo "" >> $SNAPSHOT_FILE
echo "# Memory" >> $SNAPSHOT_FILE
free -h | grep Mem | awk '{print "m:" $2}' >> $SNAPSHOT_FILE

echo "Snapshot saved to $SNAPSHOT_FILE"
echo "ClaudeScript format snapshot created successfully."

# Copy the latest snapshot to a fixed location for the Claude plugin
cp $SNAPSHOT_FILE ~/.TheArchHive/latest_snapshot.txt
