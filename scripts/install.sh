
#!/bin/bash
set -e

echo "Installerar InfoMagic..."

apt update
apt install -y nodejs npm sharp cec-utils

useradd -r -s /usr/sbin/nologin infomagic || true
mkdir -p /opt/infomagic
cp -r . /opt/infomagic
chown -R infomagic:infomagic /opt/infomagic

echo "infomagic ALL=(root) NOPASSWD: /sbin/reboot,/usr/bin/cec-client,/usr/bin/vcgencmd" > /etc/sudoers.d/infomagic

echo "Installation klar."
