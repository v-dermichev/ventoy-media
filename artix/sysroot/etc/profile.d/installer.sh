#!/bin/bash
# Switch to zsh if available and not already in zsh
if command -v zsh >/dev/null 2>&1 && [ -z "$ZSH_VERSION" ]; then
    export INSTALLER_SHOWN=1
    exec zsh
fi

# Show installer help on login
if [ -z "$INSTALLER_SHOWN" ]; then
    export INSTALLER_SHOWN=1
    bash install-help.sh 2>/dev/null
fi
