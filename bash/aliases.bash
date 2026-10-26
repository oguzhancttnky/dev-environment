# Interactive shell aliases and helpers (sourced by bash/bashrc).
# Bypass any alias with a backslash, e.g. \ls or \cat.

# ---------- ls -> eza ----------
if command -v eza >/dev/null; then
    alias ls='eza --icons=auto --group-directories-first'
    alias l='eza --icons=auto --group-directories-first -1'
    alias ll='eza --icons=auto --group-directories-first -lh --git'
    alias la='eza --icons=auto --group-directories-first -lah --git'
    alias lt='eza --icons=auto --group-directories-first --tree --level=2'
    alias lta='eza --icons=auto --group-directories-first --tree --level=2 -a --ignore-glob=.git'
else
    alias ll='ls -alFh'
    alias la='ls -A'
    alias l='ls -CF'
fi

# ---------- cat -> bat ----------
if command -v bat >/dev/null; then
    export BAT_THEME="Catppuccin Mocha"
    alias cat='bat --paging=never --style=plain'
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
    export MANROFFOPT="-c"
fi

# ---------- navigation ----------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

mkcd() {
    mkdir -p -- "$1" && cd -- "$1"
}

# ---------- safer file operations ----------
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'
alias mkdir='mkdir -p'

# ---------- human readable output ----------
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias duh='du -h --max-depth=1 | sort -hr'

# ---------- shortcuts ----------
alias c='clear'
alias q='exit'
alias h='history | grep'
alias path='tr ":" "\n" <<<"$PATH"'
alias reload='source ~/.bashrc'
alias open='xdg-open'
alias ports='ss -tulpn'
alias myip='curl -s https://ifconfig.me; echo'
alias localip="hostname -I | awk '{print \$1}'"
alias serve='python3 -m http.server'
alias now='date +"%Y-%m-%d %H:%M:%S"'

# Extract any common archive: extract file.tar.gz
extract() {
    if [ ! -f "$1" ]; then
        echo "extract: '$1' is not a file" >&2
        return 1
    fi
    case "$1" in
        *.tar.bz2 | *.tbz2) tar xjf "$1" ;;
        *.tar.gz | *.tgz) tar xzf "$1" ;;
        *.tar.xz | *.txz) tar xJf "$1" ;;
        *.tar.zst) tar --zstd -xf "$1" ;;
        *.tar) tar xf "$1" ;;
        *.bz2) bunzip2 "$1" ;;
        *.gz) gunzip "$1" ;;
        *.xz) unxz "$1" ;;
        *.zip) unzip "$1" ;;
        *.7z) 7z x "$1" ;;
        *.rar) unrar x "$1" ;;
        *) echo "extract: don't know how to extract '$1'" >&2; return 1 ;;
    esac
}
