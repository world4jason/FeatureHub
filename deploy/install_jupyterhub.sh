#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# Setup

set -e
set -x

function print_usage {
    echo "usage: install_jupyterhub.sh ff_app_name ff_image_name"
    echo "                             jupyterhub_config_dir mysql_container_name"
}

function print_usage_and_die {
    print_usage
    echo "Error: $1"
    exit 1
}

# ------------------------------------------------------------------------------
# App config
if [ "$#" != "4" ]; then
    print_usage_and_die "Invalid number of arguments."
fi

FF_APP_NAME="$1"
FF_IMAGE_NAME="$2"
JUPYTERHUB_CONFIG_DIR="$3"
MYSQL_CONTAINER_NAME="$4"

# ------------------------------------------------------------------------------
# Install dependencies

echo "Installing jupyterhub dependencies..."

if [ "$PKG_MGR" = "apt-get" ]; then
    sudo apt-get -y install npm nodejs-legacy
elif [ "$PKG_MGR" = "yum" ]; then
    # sketchy!!!!!! untrusted code
    curl --silent --location https://rpm.nodesource.com/setup_${NODE_VERSION}.x | sudo bash -
    sudo yum -y install nodejs
fi

sudo npm install -g configurable-http-proxy
sudo pip3 install jupyterhub

# ------------------------------------------------------------------------------
# Generate SSL certificate

echo "Generating SSL certificate..."

KEY_NAME="featurefactory_${FF_APP_NAME}_key.pem"
CERT_NAME="featurefactory_${FF_APP_NAME}_cert.pem"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$JUPYTERHUB_CONFIG_DIR/$KEY_NAME" \
    -out "$JUPYTERHUB_CONFIG_DIR/$CERT_NAME" \
    -batch

# ------------------------------------------------------------------------------
# Configure jupyterhub

echo "Configuring jupyterhub..."

if [ ! -f "${JUPYTERHUB_CONFIG_DIR}/jupyterhub_config_generated.py" ]; then
    jupyterhub --generate-config -f "${JUPYTERHUB_CONFIG_DIR}/jupyterhub_config_generated.py"
fi
cp "${SCRIPT_DIR}/jupyterhub_config.py" "${JUPYTERHUB_CONFIG_DIR}"
HUB_IP="$(ip -f inet address show dev eth0 | grep inet | awk '{print $2}' | cut -d '/' -f 1)"
cat >>"${JUPYTERHUB_CONFIG_DIR}/jupyterhub_config.py" <<EOF
# System-specific configuration generated by ${SCRIPT_NAME}.
c.JupyterHub.hub_ip = '$HUB_IP'
c.JupyterHub.ssl_key = '$JUPYTERHUB_CONFIG_DIR/$KEY_NAME'
c.JupyterHub.ssl_cert = '$JUPYTERHUB_CONFIG_DIR/$CERT_NAME'
c.DockerSpawner.links = {'$MYSQL_CONTAINER_NAME':'$MYSQL_CONTAINER_NAME'}
c.SystemUserSpawner.container_image = "$FF_IMAGE_NAME"
EOF

echo "Done."

# ------------------------------------------------------------------------------
# Launch script

echo "Creating jupyterhub launch script..."

JUPYTERHUB_LAUNCH_SCRIPT_NAME="$HOME/ff_${FF_APP_NAME}_jupyterhub_launch.sh"
if [ -f "$JUPYTERHUB_LAUNCH_SCRIPT_NAME" ]; then
    rm -f "$JUPYTERHUB_LAUNCH_SCRIPT_NAME"
fi
cat >"$JUPYTERHUB_LAUNCH_SCRIPT_NAME" <<EOF
#!/usr/bin/env bash
# jupyterhub launch script generated by ${SCRIPT_NAME}.
jupyterhub -f $JUPYTERHUB_CONFIG_DIR/jupyterhub_config.py
EOF
chmod u=rx "$JUPYTERHUB_LAUNCH_SCRIPT_NAME"

echo "Done."
