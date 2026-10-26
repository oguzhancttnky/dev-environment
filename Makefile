BASHRC_LINE = [ -f "$(PWD)/bash/bashrc" ] && source "$(PWD)/bash/bashrc"

all: clean sync

sync:
	grep -qF '$(BASHRC_LINE)' ~/.bashrc || printf '\n# dev-environment\n%s\n' '$(BASHRC_LINE)' >> ~/.bashrc
	mkdir -p ~/.config
	[ -L ~/.config/starship.toml ] || ln -s $(PWD)/bash/starship.toml ~/.config/starship.toml
	[ -L ~/.blerc ] || ln -s $(PWD)/bash/blerc ~/.blerc
	[ -f ~/.gitconfig ] || ln -s $(PWD)/.gitconfig ~/.gitconfig

clean:
	rm -rf ~/.config/starship.toml || true
	rm -rf ~/.blerc || true
	rm -rf ~/.gitconfig || true

.PHONY: all clean sync
