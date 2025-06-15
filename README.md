# teleyaya
El **objetivo de este proyecto es controlar una televisión Android SmartTV de forma remota desde distintos hogares**. Será imprescindible levantar una VPN para que ambos dispositivos puedan entablar conexión.

<div style="display: flex; align-items: center; gap: 10px;">
  <img src="images/clouding/clouding-logo.png" width="400">
  <img src="images/vpn/wireguard-logo.png" width="200">
</div>

**Requisitos** previos:
- **Contar con una SmartTV compatible**. En este ejemplo se ha utilizado un Google Chromecast y una SmartTV TCL. Sin embargo, **algunas marcas tienen restringido los permisos a las opciones de desarrollador**, siendo necesarias para este cometido.
- **Contar con las herramientas de desarrollo para Android**. Es posible descargarlas desde [platform-tools](https://developer.android.com/tools/releases/platform-tools?hl=es-419). Una vez descargadas las almacenaremos en la carpeta que deseemos y procederemos agregar el PATH de la misma al conjunto de variables de entorno.

---

# Levantar una VPN propia
## Servidor en Clouding
Primero levantamos un servidor en la nube mediante el proveedor Clouding. Creamos una máquina **Ubuntu 22** con las especificaciones mínimas posibles.

![](images/clouding/Clouding-1.png)

![](images/clouding/Clouding-2.png)

![](images/clouding/Clouding-3.png)

![](images/cloudingClouding-4.png)

![](images/cloudingClouding-5.png)

Creamos el servidor.

**Por último, habilitamos el tráfico UDP por el puerto utilizado en Wireguard.**

![](images/clouding/Clouding_Firewall_Port.png)

Ahora tendremos que conectarnos mediante SSH a la máquina.

![](images/clouding/Conexion_mediante_SSH_al_servidor.png)

## Crear la VPN

![](images/vpn/WireGuard-text-Logo.png)

Se han creado los ficheros `sh/vpn.sh` y `sh/add_peer.sh` para la creación de la VPN y la agregación de un nuevo cliente respectivamente. Ambos cuentan con una explicación breve paso por paso de lo que se va explicar a continuación de forma detallada.

## ⚙️ Instalación del Servidor WireGuard

#### 1. Instalar WireGuard y herramientas necesarias

```bash
sudo apt update
sudo apt install wireguard ufw iptables-persistent qrencode iftop nload -y
```

- `wireguard`: el software principal de la VPN.
- `ufw`: firewall sencillo para gestionar reglas.
- `iptables-persistent`: permite guardar reglas iptables para que persistan tras reiniciar.
- `qrencode`: opcional, para generar códigos QR con la configuración de clientes.
- `iftop`: nos permite ver de forma detallada el tráfico.
- `nload`: nos permite ver de forma sencilla el tráfico por cada interfaz.
### 🔧 Configuración inicial del servidor

#### 2. Variables de entorno

Estas variables ayudan a reutilizar valores como IPs o rutas de forma coherente en los scripts.

```bash
export SERVER_PUBLIC_IP="x.x.x.x"
export SERVER_INTERFACE="eth0"
export WG_INTERFACE="wg0"
export WG_DIR="/etc/wireguard"
export CLIENTS_DIR="/etc/wireguard/clients"
export PUBLIC_KEY_FILE="vpn.pub"
export PRIVATE_KEY_FILE="vpn.key"
export VPN_MASC="172.16.0.0/24"
export VPN_IP="172.16.0.1/24"
export VPN_ROOT_IP="172.16.0"
export LISTEN_PORT="51820"
```

Puedes añadirlas al `.bashrc` para que se carguen automáticamente al iniciar sesión.
#### 3. Configuración del Firewall

```bash
sudo ufw allow ssh
```
Permite conexiones SSH, para no bloquearte al aplicar el firewall.

```bash
sudo ufw allow 51820/udp
```
WireGuard funciona sobre UDP, se permite tráfico entrante por el puerto definido.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```
Se bloquea todo el tráfico entrante por defecto, salvo los explícitamente permitidos, y se permite salida desde el servidor.

```bash
sudo ufw enable
```
Activa `ufw` y aplica todas las reglas.

### 🔐 Configuración de la VPN (WireGuard)

#### 4. Generar claves del servidor

```bash
umask 077
mkdir ~/vpn && cd ~/vpn
wg genkey | tee vpn.key | wg pubkey > vpn.pub
```

- `umask 077`: asegura que los archivos generados solo sean legibles por el usuario.
- `wg genkey`: genera una clave privada.
- `tee`: permite guardar la clave privada y a la vez mostrarla por pantalla.
- `wg pubkey`: genera la clave pública a partir de la privada.

#### 5. Crear archivo de configuración del servidor

```ini
[Interface]
Address = 172.16.0.1/24
ListenPort = 51820
PrivateKey = <CLAVE_PRIVADA_DEL_SERVIDOR>
SaveConfig = false
```
Este archivo define:
- La IP del servidor en la red VPN (`Address`).
- El puerto donde escucha WireGuard.
- La clave privada del servidor.
- `SaveConfig = false` evita que los cambios dinámicos se sobreescriban automáticamente.

```bash
sudo chmod 600 /etc/wireguard/wg0.conf
sudo systemctl enable wg-quick@wg0
```
Restringe permisos de lectura/escritura para evitar accesos no autorizados y activa la interfaz VPN `wg0`.

### 🔄 Reenvío de tráfico (IP Forwarding)
WireGuard funciona como una interfaz virtual que necesita reenviar tráfico entre redes. Hay que habilitar el "IP forwarding" en el sistema.

```bash
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```
Habilita reenvío de paquetes IPv4 temporal y permanentemente.

### 🔒 Reglas de iptables (Firewall del servidor)

Una vez configurada la VPN, es necesario establecer reglas de firewall que permitan el reenvío de paquetes y el acceso a Internet desde los clientes de la VPN. Estas reglas se aplican utilizando iptables.

✅ Permitir tráfico entre clientes VPN

```
sudo iptables -A FORWARD -i wg0 -s 172.16.0.0/24 -d 172.16.0.0/24 -j ACCEPT
```

¿Qué hace esta regla?
- `-A FORWARD`: Añade una regla a la cadena FORWARD, que controla el tráfico que pasa a través del servidor (no el que se origina o termina en él).
- `-i wg0`: La regla aplica a paquetes entrantes por la interfaz WireGuard (wg0).
- `-s 172.16.0.0/24`: Solo paquetes que vienen desde la red VPN.
- `-d 172.16.0.0/24`: Solo paquetes que van hacia la red VPN.
- `-j ACCEPT`: Si se cumplen las condiciones anteriores, se permite el reenvío de los paquetes.


🌍 Permitir acceso a Internet desde la VPN (NAT)
```
sudo iptables -t nat -A POSTROUTING -s 172.16.0.0/24 -o eth0 -j MASQUERADE
```
¿Qué hace esta regla?
- `-t nat`: Especifica que la regla se aplicará en la tabla nat, que se encarga de traducir direcciones IP (Network Address Translation).
- `-A POSTROUTING`: Añade la regla a la cadena POSTROUTING, que se ejecuta después de que el kernel haya determinado la ruta de salida del paquete.
- `-s 172.16.0.0/24`: Aplica a paquetes que salen desde la red VPN.
- `-o eth0`: Aplica a paquetes que saldrán por la interfaz pública (interfaz conectada a Internet).
- `-j MASQUERADE`: Sustituye la IP de origen del paquete por la IP pública del servidor. Esto es lo que permite que los paquetes que vienen de la VPN puedan salir a Internet correctamente.

📝 Resumen: Esta regla permite que los clientes VPN accedan a Internet a través del servidor, ocultando sus IPs internas y usando la IP pública del servidor.

💾 Guardar reglas iptables permanentemente
```
sudo netfilter-persistent save
```
Este comando guarda las reglas actuales de iptables y iptables -t nat en archivos persistentes en:
- `/etc/iptables/rules.v4` (para IPv4)
- `/etc/iptables/rules.v6` (para IPv6)
📌 Esto es importante, ya que sin esta acción, las reglas se perderían al reiniciar el sistema.
#### 🟢 Arrancar el servicio

```bash
sudo systemctl start wg-quick@wg0
sudo systemctl status wg-quick@wg0
```

---
## 👤 Añadir Clientes (Peers)

Cuando quieres añadir un nuevo cliente (peer) a la VPN, necesitas:

1. Generar un par de claves (pública y privada) para el cliente.
2. Asignarle una IP dentro del rango VPN.
3. Añadir su clave pública al servidor.
4. Crear un archivo de configuración `.conf` en el cliente con todos los datos necesarios para establecer la conexión.
#### 🧱 1. Fichero de configuración del cliente (peer)

El archivo suele llamarse algo como `nombre_cliente.conf` y tiene esta estructura:

```ini
[Interface]
PrivateKey = <clave_privada_del_cliente>
Address = 172.16.0.X/32
DNS = 172.16.0.1

[Peer]
PublicKey = <clave_publica_del_servidor>
Endpoint = <IP_PUBLICA_SERVIDOR>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

##### Explicación campo a campo:
###### Interface (configuración local del cliente)
- `PrivateKey`: Clave **privada** del cliente. Solo debe conocerla el cliente.
- `Address`: IP interna del cliente dentro de la red VPN. Ej: `172.16.0.3/32`.
- `DNS`: IP del servidor VPN que actuará como DNS si el cliente redirige todo el tráfico por la VPN.
###### Peer (configuración del servidor)
- `PublicKey`: Clave **pública** del servidor. El cliente la necesita para verificar la identidad del servidor.
- `Endpoint`: Dirección IP pública y puerto del servidor.
- `AllowedIPs`: Qué tráfico se envía por el túnel. `0.0.0.0/0` para todo el tráfico.
- `PersistentKeepalive`: Mantiene el túnel activo en conexiones NAT.
#### 🛠 2. ¿Qué se debe configurar en el servidor?

Cuando añades un cliente nuevo, el servidor debe incluir su clave pública e IP en su archivo de configuración:
```ini
[Peer]
PublicKey = <clave_publica_cliente>
AllowedIPs = 172.16.0.X/32
```
También puede hacerse dinámicamente con:
```bash
sudo wg set wg0 peer <clave_publica_cliente> allowed-ips 172.16.0.X/32
```
> ⚠️ Este método no es persistente, se pierde tras reiniciar si no se guarda en el `.conf`.
#### 🔌 3. ¿Qué necesita el cliente para conectarse?

Una vez que el servidor ha sido configurado para aceptar al cliente, este debe:
- Tener su archivo `.conf` correctamente configurado (como vimos arriba).
- Instalar WireGuard en su dispositivo.
- Activar la interfaz con:
```bash
sudo wg-quick up nombre_cliente.conf
```
En dispositivos móviles (Android/iOS), se puede importar el archivo `.conf` o escanear un código QR generado con `qrencode`.

---

## 🔐 ¿Qué tipo de claves usa WireGuard?

WireGuard utiliza claves **de curva elíptica (Elliptic Curve Cryptography)**, específicamente:
#### 🔑 **Claves Curve25519 (privadas de 256 bits)**

- **Actualmente se consideran extremadamente seguras.**
- Equivalente aproximado de seguridad: comparable a **3072 bits RSA**.
- Generadas con `wg genkey` → 32 bytes (256 bits) aleatorios.
- Usadas en `X25519`, un protocolo robusto y eficiente.

---

# Controlar SmartTV de forma remota

## Conectar nuestra SmartTV a nuestra VPN.

### Habilitar las opciones de desarrollador

![](images/configuration/1.png)

El primer paso será habilitar las opciones de desarrollador en la SmartTV. Para ello, nos iremos al apartado de: 

1. Ajustes. 
![](images/configuration/2.png)
2. Sistema e información. 
![](images/configuration/3.png)
3. Compilación del SO de Android TV (**pulsaremos múltiples veces para desbloquear las opciones de desarrollador hasta que aparezca el mensaje**). Una vez hecho esto, volvemos al menú anterior. 
![](images/configuration/4.png)
4. Opciones de desarrollador. 
![](images/configuration/5.png)
5. Activamos la depuración USB. 
![](images/configuration/6.png)

### Configurar Wireguard en la SmartTV

Para configurar WireGuard en el dispositivo, deberemos contar con un fichero de configuración para el dispositivo (ver la documentación de WireGuard). Una vez con esto, deberemos realizar los siguientes pasos:

1. Instalar Wireguard desde la tienda de aplicaciones. 
![](images/configuration/7.png)
2. Abrimos la aplicación, seleccionamos sobre el botón de agregar nueva red y **nos pedirá que instalemos un Gestor de ficheros**. 
![](images/configuration/8.png)
3. Automáticamente nos redirigirá a instalar **Cx Explorador de Archivos**. Lo abrimos y le otargamos permisos de escritura. 
![](images/configuration/9.png)
4. Abrimos la aplicación y nos dirigimos a la sección de red y levantamos el servicio FTP. 
![](images/configuration/10.png) 
![](images/configuration/11.png) 
![](images/configuration/12.png)

5. Desde otro equipo (en este caso Windows), debemos conectarnos para enviar el fichero de configuración. Para ello **agregaremos una nueva ubicación de la red local**. 
![](images/configuration/13.png) 
![](images/configuration/14.png) 
![](images/configuration/15.png)
6. Al finalizar el proceso, nos pedirá que introduzcamos la contraseña. 
![](images/configuration/16.png)
7. Creamos una carpeta donde alojar la configuración de Wireguard (recomendado) y dejamos el fichero de configuración. 
![](images/configuration/17.png) 
Una vez hecho esto, podremos borrar la ubicación de red local.
8. Desde la SmartTV deberemos buscar el fichero de configuración compartido. 
![](images/configuration/18.png)
![](images/configuration/19.png) 
![](images/configuration/20.png)
9. Seleccionaremos la configuración cargada. 
![](images/configuration/21.png)

### Conectarnos de forma remota

Para conectarnos de forma remota desde un PC, seguiremos los siguientes pasos:

1. Nos conectamos a nuestra VPN utilizando la aplicación de escritorio de Wireguard. 
![](images/configuration/22.png)
2. Comprobamos que llegamos a la SmartTV con el comando: 
   `ping 172.16.X.X`
   ![](images/configuration/23.png)
3. Si tenemos conexión, **nos conectamos usando el comando: 
   `adb connect 172.16.X.X`**
   En ese momento, desde la SmartTV se nos pedirá confirmación para vincularse con el PC. **Deberemos de marcar la opción de 'Permitir siempre desde este ordenador'**.  
   ![](images/configuration/25.png)

4. Por último, usaremos el comando `scrcpy` para ver la pantalla de la SmartTV. 
   ![](images/configuration/24.png)
   ![](images/configuration/26.png)

Con esto ya seremos capaz de ver y controlar el dispositivo de forma remota. 

##### ⚠️ Advertencia
Al ejecutar el comando `scrcpy`, **el audio de la televisión solo podrá ser escuchado en el PC.** Una vez que cerremos la conexión el audio volverá a escucharse en la SmartTV. 

**Es posible conectarse sin recibir audio utilizando el comando `scrcpy --no-audio`**. Pero entonces, **no se mostrará ningún contenido de vídeo**. Es decir, podremos controlar la SmartTV de forma remota, pero en el momento que iniciemos la reproducción de un vídeo en Youtube (por ejemplo), veremos la retransmisión en negro (desde la SmartTV seguiremos viendo el contenido sin ningún inconveniente).

### 🎮 Controles desde el teclado con scrcpy

| Función en la TV  | Tecla en el teclado |
| :---------------: | :-----------------: |
| Dirección ↑ ↓ ← → |  Flechas dirección  |
|   Aceptar / OK    |        Enter        |
|       Atrás       |         Esc         |

Es posible utilizar los gestos en el trackpad de un portátil para moverse por la pantalla.

