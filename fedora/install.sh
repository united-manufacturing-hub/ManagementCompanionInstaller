#!/bin/bash

export INSTALL_K3S_VERSION=v1.28.2+k3s1
export INSTALL_KUBECTL_VERSION=v1.28.2

# Summary of changes to be done #600
echo "This script will perform the following actions on your system:"
echo "1. Check for necessary prerequisites."
echo "2. Install k3s and kubectl if not already installed."
echo "3. Disable the firewall (as per k3s documentation for RHEL/CentOS/Fedora)."
echo "4. Install or overwrite MgmtCompanion."

# Ask user for confirmation
read -p "Do you want to continue? (Y/n): " confirm
confirm=${confirm:-Y}
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Aborting..."
    exit 1
fi

# The install script shall check if executed as root user, and abort if not #572
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   echo "Tip: Use 'sudo ./scriptname.sh' to run it as root or use the following command:"
   echo "curl -sSL https://management.umh.app/static/fedora/install.sh | AUTH_TOKEN=<instance-installation-token> sudo -E bash"
   exit 1
fi

# The install script shall check if the authentication token is present #574
if [[ -z "$AUTH_TOKEN" ]]; then
    echo "Error: Authentication token is not present."
    echo "Tip: Ensure you've included the AUTH_TOKEN in your command. Example:"
    echo "curl -sSL https://management.umh.app/static/fedora/install.sh | AUTH_TOKEN=<instance-installation-token> sudo -E bash"
    exit 1
fi

# Validate AUTH_TOKEN format
if [[ ! "$AUTH_TOKEN" =~ ^[a-fA-F0-9]{64}$ ]]; then
    echo "Error: Invalid authentication token format."
    echo "Tip: Ensure your authentication token is a 256-bit hex-encoded string."
    exit 1
fi

# Check if the RHEL machine is registered
if ! subscription-manager status &> /dev/null; then
    echo "Error: Your RHEL machine is not registered."
    echo "Tip: Register your machine with 'subscription-manager register' and run the script again."
    exit 1
fi

# Check RHEL version
RHEL_VERSION=$(grep -oP '(?<= )[0-9]+(?=\.?)' /etc/redhat-release | head -1)
if [[ ! "$RHEL_VERSION" =~ ^(7|8|9)$ ]]; then
    echo "Error: Unsupported RHEL version. Supported versions are 7, 8, and 9."
    exit 1
fi

# Ensure curl is installed (this should never happen, as we use curl to download the script, but just in case)
if ! command -v curl &> /dev/null; then
    echo "curl is not installed. Installing curl..."
    if ! yum install -y curl; then
        echo "Error: Failed to install curl."
        echo "Tip: Check your network connection or install curl manually using 'sudo yum install curl' and run the script again."
        exit 1
    fi
fi

# The install script shall check if k3s is installed, and if not install it #575
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io -o k3s-install.sh
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download k3s-install.sh."
        echo "Tip: Check your network connection or download k3s-install.sh manually from https://get.k3s.io and run the script again."
        exit 1
    fi
    if ! bash k3s-install.sh; then
        echo "Error: Failed to install k3s."
        echo "Tip: Check the logs above for any error messages."
        exit 1
    fi
    rm k3s-install.sh
fi

# The install script shall check if kubectl is installed or install it #576
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$INSTALL_KUBECTL_VERSION/bin/linux/amd64/kubectl" -o kubectl
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download kubectl."
        echo "Tip: Check your network connection or download kubectl manually from https://kubernetes.io/docs/tasks/tools/install-kubectl/ and place it in your PATH."
        exit 1
    fi
    chmod +x kubectl
    mv kubectl /usr/local/bin/
fi

# The install script shall disable the firewall for RHEL/CentOS/Fedora as per k3s documentation
if ! systemctl disable --now firewalld; then
    echo "Error: Failed to disable the firewall."
    echo "Tip: Manually disable the firewall using 'sudo systemctl disable --now firewalld' and run the script again."
    exit 1
fi

# The install script shall detect if MgmgCompanion is already installed #577
if kubectl get namespace mgmtcompanion &> /dev/null; then
    echo "MgmtCompanion is already installed."

    # If the install script detects an existing MgmtCompanion installation it shall ask the user if he wants to overwrite or abort #578
    read -p "Do you want to overwrite the existing installation? (y/N): " overwrite_confirm
    overwrite_confirm=${overwrite_confirm:-N}
    if [[ ! $overwrite_confirm =~ ^[Yy]$ ]]; then
        echo "Aborting..."
        exit 1
    fi
    echo "Overwriting existing installation..."
    # Remove namespace and all resources inside it
    if kubectl delete namespace mgmtcompanion; then
        echo "Existing installation removed."
    else
        echo "Error: Failed to remove existing installation."
        echo "Tip: Check the logs above for any error messages."
        exit 1
    fi
fi

# Install MgmtCompanion
echo "Installing MgmtCompanion..."
## Create namespace
if ! kubectl create namespace mgmtcompanion; then
    echo "Error: Failed to create namespace."
    echo "Tip: Check the logs above for any error messages."
    exit 1
fi

## Download the MgmtCompanion manifests (configmap, secret, statefulset)
if ! curl -sSL https://management.umh.app/static/kubernetes/configmap.yaml -o /tmp/configmap.yaml; then
    echo "Error: Failed to download configmap.yaml."
    echo "Tip: Check your network connection"
    exit 1
fi
if ! curl -sSL https://management.umh.app/static/kubernetes/secret.yaml -o /tmp/secret.yaml; then
    echo "Error: Failed to download secret.yaml."
    echo "Tip: Check your network connection"
    exit 1
fi
if ! curl -sSL https://management.umh.app/static/kubernetes/statefulset.yaml -o /tmp/statefulset.yaml; then
    echo "Error: Failed to download statefulset.yaml."
    echo "Tip: Check your network connection"
    exit 1
fi

## Apply the MgmtCompanion manifests
if ! kubectl apply -f /tmp/configmap.yaml -n mgmtcompanion; then
    echo "Error: Failed to apply configmap.yaml."
    echo "Tip: Check the logs above for any error messages."
    exit 1
fi
if ! kubectl apply -f /tmp/secret.yaml -n mgmtcompanion; then
    echo "Error: Failed to apply secret.yaml."
    echo "Tip: Check the logs above for any error messages."
    exit 1
fi
if ! kubectl apply -f /tmp/statefulset.yaml -n mgmtcompanion; then
    echo "Error: Failed to apply statefulset.yaml."
    echo "Tip: Check the logs above for any error messages."
    exit 1
fi

## Wait a few seconds for the pod to start
sleep 5

# Check for successful installation by querying k3s to check if the following is true (all resources are inside the mgmtcompanion namespace)
# - statefulset: mgmtcompanion
# - secret: mgmtcompanion-secret
# - configmap: mgmtcompanion-config
if [[ $(kubectl get statefulsets -n mgmtcompanion --field-selector metadata.name=mgmtcompanion -o jsonpath='{.items[*].metadata.name}') == "mgmtcompanion" ]] &&
   [[ $(kubectl get secrets -n mgmtcompanion --field-selector metadata.name=mgmtcompanion-secret -o jsonpath='{.items[*].metadata.name}') == "mgmtcompanion-secret" ]] &&
   [[ $(kubectl get configmaps -n mgmtcompanion --field-selector metadata.name=mgmtcompanion-config -o jsonpath='{.items[*].metadata.name}') == "mgmtcompanion-config" ]]; then

    mgmtcompanion_pod=$(kubectl get pods -n mgmtcompanion --selector=statefulset.kubernetes.io/pod-name=mgmtcompanion-0 -o jsonpath='{.items[*].metadata.name}')
    TIMEOUT=300  # 5 minutes
    INTERVAL=5   # check every 5 seconds
    ELAPSED=0
    while [[ $(kubectl get pod $mgmtcompanion_pod -n mgmtcompanion -o jsonpath='{.status.phase}') != "Running" && $ELAPSED -lt $TIMEOUT ]]; do
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    if [[ $(kubectl get pod $mgmtcompanion_pod -n mgmtcompanion -o jsonpath='{.status.phase}') == "Running" ]]; then
        echo "Installation successful."
    else
        echo "Error: Installation failed - mgmtcompanion pod is not running."
        echo "Tip: Check the pod's logs with 'kubectl logs $mgmtcompanion_pod -n mgmtcompanion' for more details."
        exit 1
    fi
else
    echo "Error: Installation failed - Required resources are missing in the mgmtcompanion namespace."
    echo "Tip: Verify the installation steps and ensure all necessary resources are created."
    exit 1
fi
