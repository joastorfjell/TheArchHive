# ThinkPad Setup Guide

This guide contains ThinkPad-specific setup instructions for Arch Linux.

## Pre-installation

1. Update BIOS to the latest version
2. In BIOS settings:
   - Disable Secure Boot
   - Set SATA mode to AHCI
   - Enable virtualization if needed

## Installation

Follow the standard Arch installation guide, but note these ThinkPad-specific points:

1. For wireless during installation, you may need to install `iwlwifi` firmware
2. For better power management, install `tlp` and `acpi`

## Post-installation

1. Install ThinkPad-specific packages:
sudo pacman -S acpi_call tp_smapi tlp

2. Enable and start TLP for better battery life:
sudo systemctl enable tlp.service
sudo systemctl start tlp.service

3. Configure TrackPoint/TouchPad:
# Create a config file for better sensitivity
sudo mkdir -p /etc/X11/xorg.conf.d/
sudo cat > /etc/X11/xorg.conf.d/30-touchpad.conf << 'CONF'
Section "InputClass"
Identifier "touchpad"
Driver "libinput"
MatchIsTouchpad "on"
Option "Tapping" "on"
Option "NaturalScrolling" "true"
EndSection
CONF

4. Setup function keys:
# Install xbindkeys and xev
sudo pacman -S xbindkeys xorg-xev

## Hardware-specific notes

- ThinkPad models with hybrid graphics (NVIDIA/Intel):
Consider using `optimus-manager` or `bumblebee` for graphics switching

- For fingerprint reader:
Install `fprintd` package and configure PAM
