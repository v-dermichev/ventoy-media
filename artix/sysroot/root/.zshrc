# Minimal zshrc for installer — ASCII safe
autoload -U compinit && compinit
setopt AUTO_CD
setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY

HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=1000

# Prompt — ASCII safe
PS1='%~ > '

# Aliases
alias ll='ls -lah --color=auto'
alias l='ls -la --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'

# Installer shortcuts
alias install-system='bash install-artix.sh'
alias install-help='bash install-help.sh'
alias partition='bash partition-disk.sh'
alias wifi='bash wifi-connect.sh'

# fzf key bindings if available
if command -v fzf >/dev/null 2>&1; then
    fdo() {
        local cmd=$1
        shift
        local file
        file=$(fzf "$@") || return
        $cmd "$file"
    }
fi

install-help 2>/dev/null
