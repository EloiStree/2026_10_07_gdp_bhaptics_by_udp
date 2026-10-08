```
git submodule add https://github.com/EloiStree/2026_10_07_gdp_bhaptics_by_udp.git addons/2026_10_07_gdp_bhaptics_by_udp
```
```
git clone https://github.com/EloiStree/2026_10_07_gdp_bhaptics_by_udp.git addons/2026_10_07_gdp_bhaptics_by_udp
```
# 2026_10_07_gdp_bhaptics_by_udp

Godot code for using UDP in OSC format to control your bHaptics suit.   
  
⚠️ The code is vibe-coded for now. I still need to understand it properly and clean it up.   
⚠️ Feel free to fork it and use it in your project.  
I don't have a development branch and often change the code when the GOMI app needs it.   
  
See: https://github.com/EloiStree/GOMI   


# bHaptics Setup Guide

## Manual

Refer to the official bHaptics documentation for the initial setup:

https://docs.bhaptics.com/start-here/getting-started

## Download bHaptics Player for Windows

Download and install the **bHaptics Player for Windows**:

[<img width="1530" height="515" alt="Download bHaptics Player for Windows" src="https://github.com/user-attachments/assets/a636a2e5-9cad-4613-a3eb-a3e43f43cb7c" />](https://www.bhaptics.com/games/vr/software/)

https://www.bhaptics.com/games/vr/software/

## Setup the Software

### 1. Update the Firmware

Open the bHaptics Player and update the firmware of your suit to the latest version.

<img width="789" height="70" alt="Update Firmware" src="https://github.com/user-attachments/assets/119f659b-8d7e-49fd-b8c4-286eb29a7393" />

### 2. Open the Application Settings

Open the **Settings** menu in the bHaptics Player.

<img width="956" height="241" alt="Open Settings" src="https://github.com/user-attachments/assets/3d1887ef-f836-48d5-94e4-f82724736e35" />

### 3. Enable OSC Support

Enable **OSC Support** in the application settings.

<img width="829" height="639" alt="Enable OSC Support" src="https://github.com/user-attachments/assets/a117d5c5-3f20-416f-a48e-0fd9590bbdf4" />

If you want to control the suit from another device on the network, set the OSC listening address to **0.0.0.0**.

### 4. Allow the Application to Listen on the OSC Port

Add the application you want to use to the application list. This allows the application to listen on the configured OSC port and communicate with the bHaptics Player.
