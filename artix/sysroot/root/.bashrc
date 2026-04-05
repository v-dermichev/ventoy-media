# Switch to zsh if available
if command -v zsh >/dev/null 2>&1; then
    exec zsh
fi

# Installer shortcuts (fallback if zsh unavailable)
alias install-system='bash install-artix.sh'
alias install-help='bash install-help.sh'
alias partition='bash partition-disk.sh'
alias wifi='bash wifi-connect.sh'
