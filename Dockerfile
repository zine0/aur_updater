FROM archlinux/base:latest

# 安装必要软件
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    git \
    curl \
    sed \
    grep \
    bash \
    sudo \
    pacman-contrib

# 创建非root用户用于AUR构建
RUN useradd -m -G wheel -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 切换到builder用户
USER builder
WORKDIR /home/builder

# 复制脚本
COPY aur-update.sh /home/builder/aur-update.sh
RUN chmod +x /home/builder/aur-update.sh

# 配置git
RUN git config --global user.name "GitHub Actions" && \
    git config --global user.email "actions@github.com"

ENTRYPOINT ["/home/builder/aur-update.sh"]
