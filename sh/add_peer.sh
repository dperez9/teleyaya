#!/bin/bash

# --- ENTRADA ---
CLIENT_NAME="$1"
ID="$2"
if [ -z "$CLIENT_NAME" ] || [ -z "$ID" ];; then
  echo "Error, client name and id ip required! (ID: x.x.x.ID)"
  exit 1
fi

CLIENT_DIR="${CLIENTS_DIR}/${CLIENT_NAME}"
CLIENT_IP="${VPN_ROOT_IP}.${ID}"

# --- CREAR CARPETA CLIENTS ---
sudo mkdir -p "$CLIENT_DIR"

# --- GENERAR CLAVES DEL CLIENTE ---
cd "$CLIENT_DIR"
umask 077
wg genkey | tee "${CLIENT_NAME}.key" | wg pubkey > "${CLIENT_NAME}.pub"

CLIENT_PRIVATE_KEY=$(cat "${CLIENT_NAME}.key")
CLIENT_PUBLIC_KEY=$(cat "${CLIENT_NAME}.pub")

# --- AÑADIR PEER EN CALIENTE ---
sudo wg set "$WG_INTERFACE" peer "$CLIENT_PUBLIC_KEY" allowed-ips "${CLIENT_IP}/32"

# --- AÑADIR PEER A wg0.conf ---
sudo tee -a "${WG_DIR}/${WG_INTERFACE}.conf" > /dev/null <<EOF

# ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_IP}/32
EOF

# --- CREAR CONFIGURACIÓN PARA EL CLIENTE ---
CLIENT_CONF="${CLIENT_NAME}.conf"
tee "$CLIENT_CONF" > /dev/null <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IP}/32
DNS = ${DNS}

[Peer]
PublicKey = $(sudo wg show "$WG_INTERFACE" public-key)
Endpoint = ${SERVER_PUBLIC_IP}:${LISTEN_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# --- CODIGO QR ---
if command -v qrencode &> /dev/null; then
  qrencode -o "$CLIENTS_DIR/$CLIENT_NAME/${CLIENT_NAME}.png" < "$CLIENTS_DIR/$CLIENT_NAME/${CLIENT_NAME}.conf"
  # Lo muestra por la terminal
  qrencode -t ansiutf8 < "$CLIENTS_DIR/$CLIENT_NAME/${CLIENT_NAME}.conf"
else
  echo "Install qrencode to generate a QR code for config"
fi

echo "Client '${CLIENT_NAME}' added with IP ${CLIENT_IP}"
echo "File config generated: ${CLIENTS_DIR}/${CLIENT_CONF}"
echo 'QR generated: "$CLIENTS_DIR/$CLIENT_NAME/${CLIENT_NAME}.png"'