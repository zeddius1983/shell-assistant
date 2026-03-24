FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=/bin/zsh

# Core packages and ZSH plugins
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    wget \
    gpg \
    ca-certificates \
    zsh \
    zsh-syntax-highlighting \
    zsh-autosuggestions \
    zoxide \
    fzf \
    direnv \
    bat \
    ripgrep \
    fd-find \
    python3 \
    less \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Fix executable names for bat and fd-find on Ubuntu
RUN ln -s /usr/bin/batcat /usr/local/bin/bat || true
RUN ln -s /usr/bin/fdfind /usr/local/bin/fd || true

# Install Atuin
RUN bash -c "$(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)" \
    && ln -s /root/.atuin/bin/atuin /usr/local/bin/atuin || true

# Install eza
RUN mkdir -p /etc/apt/keyrings \
    && wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" > /etc/apt/sources.list.d/gierens.list \
    && chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list \
    && apt-get update && apt-get install -y --no-install-recommends eza \
    && rm -rf /var/lib/apt/lists/*

# Install glow
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list \
    && apt-get update && apt-get install -y --no-install-recommends glow \
    && rm -rf /var/lib/apt/lists/*

# Install starship and copy its config
RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes
RUN mkdir -p /root/.config
COPY starship.toml /root/.config/starship.toml

# Install shai globally so it doesn't get shadowed by volume mounts
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && env UV_TOOL_DIR=/opt/uv UV_TOOL_BIN_DIR=/usr/local/bin /root/.local/bin/uv tool install git+https://github.com/zeddius1983/shell-assistant.git --refresh

# Configure /root/.zshrc
RUN echo 'export PATH="/usr/local/bin:$PATH"' >> /root/.zshrc \
    && echo 'source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' >> /root/.zshrc \
    && echo 'source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh' >> /root/.zshrc \
    && echo 'eval "$(starship init zsh)"' >> /root/.zshrc \
    && echo 'eval "$(zoxide init zsh)"' >> /root/.zshrc \
    && curl -sSLo /root/.fzf-key-bindings.zsh https://raw.githubusercontent.com/junegunn/fzf/master/shell/key-bindings.zsh \
    && curl -sSLo /root/.fzf-completion.zsh https://raw.githubusercontent.com/junegunn/fzf/master/shell/completion.zsh \
    && echo 'source /root/.fzf-key-bindings.zsh' >> /root/.zshrc \
    && echo 'source /root/.fzf-completion.zsh' >> /root/.zshrc \
    && echo 'eval "$(atuin init zsh)"' >> /root/.zshrc \
    && echo 'eval "$(direnv hook zsh)"' >> /root/.zshrc \
    && echo "alias ls='eza --icons --group-directories-first'" >> /root/.zshrc \
    && echo "alias ll='eza --icons --group-directories-first -l --git'" >> /root/.zshrc \
    && echo "alias la='eza --icons --group-directories-first -la --git'" >> /root/.zshrc \
    && echo "alias lt='eza --icons --tree --level=2'" >> /root/.zshrc \
    && echo "alias lta='eza --icons --tree --level=2 -a'" >> /root/.zshrc \
    && echo "alias cat='bat'" >> /root/.zshrc \
    && echo "alias less='bat'" >> /root/.zshrc \
    && echo "alias vi='vim'" >> /root/.zshrc \
    && echo "syntax on" >> /root/.vimrc \
    && echo "set background=dark" >> /root/.vimrc \
    && echo 'source "$(/usr/local/bin/shai --shell-path zsh)"' >> /root/.zshrc

CMD ["zsh"]
