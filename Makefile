all: clean sync

sync:
	[ -f ~/.config/fish/config.fish ] || ln -s $(PWD)/fish/config.fish ~/.config/fish/config.fish
	[ -L ~/.config/fish/functions ] || ln -s $(PWD)/fish/functions ~/.config/fish/functions
	[ -f ~/.gitconfig ] || ln -s $(PWD)/.gitconfig ~/.gitconfig

clean:
	rm -rf ~/.config/fish/config.fish || true
	rm -rf ~/.config/fish/functions || true
	rm -rf ~/.gitconfig || true

.PHONY: all clean sync