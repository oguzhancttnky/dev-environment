all: clean sync

sync:
	[ -f ~/.config/fish/config.fish ] || ln -s $(PWD)/fish/config.fish ~/.config/fish/config.fish
	[ -L ~/.config/fish/functions ] || ln -s $(PWD)/fish/functions ~/.config/fish/functions
	[ -f ~/.gitconfig ] || ln -s $(PWD)/.gitconfig ~/.gitconfig

clean:
	[ -e ~/.config/fish/config.fish ] && rm -rf ~/.config/fish/config.fish
	[ -e ~/.config/fish/functions ] && rm -rf ~/.config/fish/functions
	[ -e ~/.gitconfig ] && rm -rf ~/.gitconfig

.PHONY: all clean sync