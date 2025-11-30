all: clean sync

sync:
	[ -L ~/.config/fish/fish_plugins ] || ln -s $(PWD)/fish/fish_plugins ~/.config/fish/fish_plugins
	[ -f ~/.config/fish/config.fish ] || ln -s $(PWD)/fish/config.fish ~/.config/fish/config.fish
	[ -L ~/.config/fish/functions ] || ln -s $(PWD)/fish/functions ~/.config/fish/functions
	[ -f ~/.gitconfig ] || ln -s $(PWD)/.gitconfig ~/.gitconfig

clean:
	rm -rf ~/.config/fish/fish_plugins || true
	rm -rf ~/.config/fish/config.fish || true
	rm -rf ~/.config/fish/functions || true
	rm -rf ~/.gitconfig || true

.PHONY: all clean sync