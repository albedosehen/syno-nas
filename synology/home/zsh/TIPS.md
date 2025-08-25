# TIPS for Zsh on Synology NAS

## Zsh Syno Setup

> Ensure Zsh binary is executable by all users

```shell
sudo sh -c 'grep -qxF /opt/bin/zsh /etc/shells || echo /opt/bin/zsh >> /etc/shells'
```

> Ensure Entware is on PATH for new sessions

```shell
grep -q '/opt/bin' ~/.profile || echo 'export PATH=/opt/bin:/opt/sbin:$PATH' >> ~/.profile; . ~/.profile
```

> Allow zsh-as-login

```shell
sudo sh -c 'grep -qxF /opt/bin/zsh /etc/shells || echo /opt/bin/zsh >> /etc/shells'
```

> Auto-start zsh on SSH login

```shell
grep -q 'exec /opt/bin/zsh -l' ~/.profile || printf '\nif [ -t 1 ] && [ -x /opt/bin/zsh ] && [ -z "$ZSH_VERSION" ]; then exec /opt/bin/zsh -l; fi\n' >> ~/.profile
```

## Oh-My-Zsh Syno Setup

> Install `oh-my-zsh` into user path

```shell
ZSH="$HOME/.local/oh-my-zsh" RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(wget -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

> Post `insecure` warning fix

```shell
chmod 755 ~; [ -d ~/.local/oh-my-zsh ] && find ~/.local/oh-my-zsh -type d -exec chmod 755 {} \; && find ~/.local/oh-my-zsh -type f -exec chmod 644 {} \; ; [ -f ~/.zshrc ] && chmod 644 ~/.zshrc
```

> Completions permissions fix

```shell
chown -R $(whoami):users ~/.local/oh-my-zsh ~/.zshrc; chmod 755 ~/.local ~/.local/oh-my-zsh ~/.local/oh-my-zsh/custom; chmod -R go-w ~/.local/oh-my-zsh; chmod 644 ~/.zshrc; exec zsh -l
```

> Force new files to use 022 umask

```shell
grep -q '^umask 022' ~/.profile || echo 'umask 022' >> ~/.profile
```
