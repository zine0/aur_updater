FROM archlinux:latest

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
    pacman-contrib \
    jq \
    openssh

# 创建非root用户用于AUR构建
RUN useradd -m -G wheel -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 复制脚本（在切换用户之前）
COPY ./updater.sh /home/builder/updater.sh
COPY ./build.sh /home/builder/build.sh
RUN chmod +x /home/builder/updater.sh
RUN chmod +x /home/builder/build.sh

# 切换到builder用户
USER builder
WORKDIR /home/builder



ENTRYPOINT ["/home/builder/build.sh"]
