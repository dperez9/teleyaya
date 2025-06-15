#!/bin/bash

# --- ENTRADA ---

SERVER_PUBLIC_IP="$1"
SERVER_INTERFACE="$2"

if [ -z "$SERVER_PUBLIC_IP" ] || [ -z "$SERVER_INTERFACE" ]; then
  echo "Use: $0 <SERVER_PUBLIC_IP> <SERVER_INTERFACE>"
  echo "O stablish SERVER_PUBLIC_IP and SERVER_INTERFACE"
  exit 1
fi

sudo apt update
sudo apt install net-tools wireguard wireguard-tools ufw netfilter-persistent iptables-persistent qrencode iftop nload -y

# Preparamos las variables de entorno
#SERVER_PUBLIC_IP="x.x.x.x"
#SERVER_INTERFACE="eth0"
DNS="1.1.1.1,8.8.8.8"
WG_INTERFACE="wg0"
WG_DIR="/etc/wireguard"
CLIENTS_DIR="/etc/wireguard/clients"
PUBLIC_KEY_FILE="vpn.pub"
PRIVATE_KEY_FILE="vpn.key"
VPN_MASC="172.16.0.0/24"
VPN_IP="172.16.0.1/24"
VPN_ROOT_IP="172.16.0"
LISTEN_PORT="51820"

cd ~; 
echo " " >> .bashrc
echo "# VPN Variables" >> .bashrc
echo "export SERVER_PUBLIC_IP=\"$SERVER_PUBLIC_IP\"" >> .bashrc
echo "export SERVER_INTERFACE=\"$SERVER_INTERFACE\"" >> .bashrc
echo 'export DNS="1.1.1.1,8.8.8.8"' >> .bashrc
echo 'export WG_INTERFACE="wg0"' >> .bashrc
echo 'export WG_DIR="/etc/wireguard"' >> .bashrc
echo 'export CLIENTS_DIR="/etc/wireguard/clients"' >> .bashrc
echo 'export PUBLIC_KEY_FILE="vpn.pub"' >> .bashrc
echo 'export PRIVATE_KEY_FILE="vpn.key"' >> .bashrc
echo 'export VPN_MASC="172.16.0.0/24"' >> .bashrc
echo 'export VPN_IP="172.16.0.1/24"' >> .bashrc
echo 'export VPN_ROOT_IP="172.16.0"' >> .bashrc
echo 'export LISTEN_PORT="51820"' >> .bashrc

# Levantamos el firewall
sudo ufw allow ssh
sudo ufw allow $LISTEN_PORT/udp # Wiregurad trabaja en este puerto
sudo ufw default deny incoming # Bloqueamos todo el trafico entrante
sudo ufw default allow outgoing # Permitimos todo el trafico de salida
sudo ufw allow in on $WG_INTERFACE # Permitir trafico entrante en la intergaz wg0
sudo ufw route allow in on $WG_INTERFACE out on eth0 # Permitir reenvio de paquetes hacia la interfaz eth0 

sudo ufw enable

umask 077 # Los proximos elementos creados se les sera revocado los persmisos de lectura y escrituras a grupos y otros
mkdir vpn; cd vpn
# Creamos el par de claves del servidor. tee es un comando de linux que muestra por pantalla y guarda en un fichero lo que recibe del comando anterior
wg genkey | tee "$PRIVATE_KEY_FILE" | wg pubkey > "$PUBLIC_KEY_FILE"

# Leemos la clave
PRIVATE_KEY=$(cat "$PRIVATE_KEY_FILE")

# Crear archivo de configuración wg0.conf
sudo tee "$WG_DIR/$WG_INTERFACE.conf" > /dev/null <<EOF
[Interface]
Address = $VPN_IP
ListenPort = $LISTEN_PORT
PrivateKey = $PRIVATE_KEY
SaveConfig = false
EOF

# Ajustar permisos. Habilitamos solo lectura y escritura 
sudo chmod 600 "$WG_DIR/$WG_INTERFACE.conf"

# Habilitar en arranque
sudo systemctl enable wg-quick@$WG_INTERFACE

# Configuramos el servidor en modo hub-and-spoke
# Habilitamos el reenvio de paquetes
sudo sysctl -w net.ipv4.ip_forward=1 # Lo habilitamos en la session
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf # Cambio permanente
sudo sysctl -p # Aplica los cambios

# tablas de rutas
# -A FORWARD: Creamos una nueva regla en los paquetes que pasan por el servidor
# -i wg0: Interfaz wg0
# -s <ip-range>: Origen de los paquetes
# -d <ip-range>: Destino de los paquetes
# -j ACCEPT: Si se cumple la definicion anterior, permite el paso
sudo iptables -A FORWARD -i "$WG_INTERFACE" -s "$VPN_MASC" -d "$VPN_MASC" -j ACCEPT

# -t nat: Aniade regla a tabla nat
# -A POSTROUTING: Añade de tipo POSTROUTING, que permite la conversion de una interfaz a otra
# -s <ip-range>: Origen de los paquetes
# -o <interface-name>: Interfaz publica(o alternativa) del servidor
# -j MASQUERADE: Reempleza la IP de origen por la del servidor
sudo iptables -t nat -A POSTROUTING -s "$VPN_MASC" -o "$SERVER_INTERFACE" -j MASQUERADE

# Guardamos la configuracion
sudo netfilter-persistent save
# Mostamos las reglas
#sudo iptables -L -v -n
#sudo iptables -t nat -L -v -n

# Arrancamos el servidor
sudo systemctl start wg-quick@$WG_INTERFACE
sudo systemctl status wg-quick@$WG_INTERFACE
# sudo systemctl restart wg-quick@$WG_INTERFACE