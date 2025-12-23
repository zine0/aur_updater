#!/usr/bin/bash
# 设置 SSH 密钥（如果在容器内运行）
setup_ssh_key() {
    if [ -n "$AUR_SSH_KEY_BASE64" ]; then
        echo "设置 SSH 密钥..."
        mkdir -p ~/.ssh
        echo "$AUR_SSH_KEY_BASE64" | base64 -d > ~/.ssh/id_rsa
        # 设置严格的权限
        chmod 600 ~/.ssh/id_rsa
        chmod 700 ~/.ssh
        # 生成公钥
        ssh-keygen -y -f ~/.ssh/id_rsa > ~/.ssh/id_rsa.pub
        chmod 644 ~/.ssh/id_rsa.pub
        # 添加 AUR 服务器到 known_hosts
        ssh-keyscan aur.archlinux.org >> ~/.ssh/known_hosts 2>/dev/null
        chmod 600 ~/.ssh/known_hosts
        echo "SSH 密钥设置完成"
    else
        echo "警告: AUR_SSH_KEY_BASE64 环境变量未设置，跳过 SSH 密钥设置"
    fi

}

setup_git() {
    git config --global user.name "$USERNAME"
    git config --global user.email "$EMAIL"
}

# 设置 SSH 密钥
setup_ssh_key
setup_git

source updater.sh

main
