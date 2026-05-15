set -gx EDITOR code
set -gx VISUAL code

fish_add_path \
    $HOME/.local/bin \
    $HOME/.cargo/bin \
    $HOME/go/bin \
    /usr/local/go/bin \
    $HOME/miniconda3/bin \
    $HOME/.opencode/bin

set fish_greeting ""
