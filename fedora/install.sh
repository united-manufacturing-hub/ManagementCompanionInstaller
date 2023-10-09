#!/bin/bash

export INSTALL_K3S_VERSION=v1.28.2+k3s1
export INSTALL_KUBECTL_VERSION=v1.28.2

# Summary of changes to be done #600
echo -e "🔍 This script will perform the following actions on your system:"
echo -e "1️⃣ Check for necessary prerequisites."
echo -e "2️⃣ Install k3s and kubectl if not already installed."
echo -e "3️⃣ Disable the firewall (as per k3s documentation for RHEL/CentOS/Fedora)."
echo -e "4️⃣ Install or overwrite MgmtCompanion."

# Ask user for confirmation
read -p "Do you want to continue? (Y/n): " confirm
confirm=${confirm:-Y}
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo -e "❌ Aborting..."
    exit 1
fi
echo -e "✅ Beginning installation..."

# The install script shall check if executed as root user, and abort if not #572
echo -e "🔍 Checking for root..."
if [[ $EUID -ne 0 ]]; then
   echo -e "❌ Error: This script must be run as root."
   echo -e "💡 Tip: Use 'sudo ./scriptname.sh' to run it as root or use the following command:"
   echo -e "curl -sSL https://management.umh.app/static/fedora/install.sh | AUTH_TOKEN=<instance-installation-token> sudo -E bash"
   exit 1
fi
echo -e "✅ Root user detected."

# The install script shall check if the authentication token is present #574
echo -e "🔍 Checking for authentication token..."
if [[ -z "$AUTH_TOKEN" ]]; then
    echo -e "❌ Error: Authentication token is not present."
    echo -e "💡 Tip: Ensure you've included the AUTH_TOKEN in your command. Example:"
    echo -e "curl -sSL https://management.umh.app/static/fedora/install.sh | AUTH_TOKEN=<instance-installation-token> sudo -E bash"
    exit 1
fi
echo -e "✅ Authentication token detected."

# Validate AUTH_TOKEN format
echo -e "🔍 Validating authentication token format..."
if [[ ! "$AUTH_TOKEN" =~ ^[a-fA-F0-9]{64}$ ]]; then
    echo -e "❌ Error: Invalid authentication token format."
    echo -e "💡 Tip: Ensure your authentication token is a 256-bit hex-encoded string."
    exit 1
fi
echo -e "✅ Authentication token format is valid."

# Check if the RHEL machine is registered
echo -e "🔍 Checking if your RHEL machine is registered..."
if ! subscription-manager status &> /dev/null; then
    echo -e "❌ Error: Your RHEL machine is not registered."
    echo -e "💡 Tip: Register your machine with 'subscription-manager register' and run the script again."
    exit 1
fi
echo -e "✅ Your RHEL machine is registered."

# Check RHEL version
echo -e "🔍 Checking RHEL version..."
RHEL_VERSION=$(grep -oP '(?<= )[0-9]+(?=\.?)' /etc/redhat-release | head -1)
if [[ ! "$RHEL_VERSION" =~ ^(7|8|9)$ ]]; then
    echo "❌ Error: Unsupported RHEL version. Supported versions are 7, 8, and 9."
    echo "💡 Tip: Check your RHEL version with 'cat /etc/redhat-release' and upgrade to a supported version."
    exit 1
fi
echo -e "✅ RHEL version $RHEL_VERSION is supported."

# Ensure curl is installed (this should never happen, as we use curl to download the script, but just in case)
echo -e "🔍 Checking for curl..."
if ! command -v curl &> /dev/null; then
    echo -e "🔧 curl is not installed. Installing curl..."
    if ! yum install -y curl; then
        echo -e "❌ Error: Failed to install curl."
        echo -e "💡 Tip: Check your network connection or install curl manually using 'sudo yum install curl' and run the script again."
        exit 1
    fi
fi
echo -e "✅ curl is installed successfully."

# The install script shall check if k3s is installed, and if not install it #575
echo -e "🔍 Checking for k3s..."
if ! command -v k3s &> /dev/null; then
    echo -e "🔧 k3s is not installed. Installing k3s..."
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
    echo -e "✅ k3s is installed successfully."
else
    echo -e "✅ k3s is already installed."
fi

# The install script shall check if kubectl is installed or install it #576
echo -e "🔍 Checking for kubectl..."
if ! command -v kubectl &> /dev/null; then
    echo -e "🔧 kubectl is not installed. Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$INSTALL_KUBECTL_VERSION/bin/linux/amd64/kubectl" -o kubectl
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download kubectl."
        echo "Tip: Check your network connection or download kubectl manually from https://kubernetes.io/docs/tasks/tools/install-kubectl/ and place it in your PATH."
        exit 1
    fi
    chmod +x kubectl
    mv kubectl /usr/local/bin/
    echo -e "✅ kubectl is installed successfully."
else
    echo -e "✅ kubectl is already installed."
fi

# The install script shall disable the firewall for RHEL/CentOS/Fedora as per k3s documentation
echo -e "🔓 Disabling the firewall..."
if ! systemctl disable --now firewalld; then
    echo -e "❌ Error: Failed to disable the firewall."
    echo -e "💡 Tip: Manually disable the firewall using 'sudo systemctl disable --now firewalld' and run the script again."
    exit 1
fi
echo -e "✅ Firewall disabled successfully."

# The install script shall detect if MgmgCompanion is already installed #577
echo -e "🔍 Checking for existing MgmtCompanion installation..."
if kubectl get namespace mgmtcompanion &> /dev/null; then
    echo -e "⚠️ MgmtCompanion is already installed."

    # If the install script detects an existing MgmtCompanion installation it shall ask the user if he wants to overwrite or abort #578
    read -p "Do you want to overwrite the existing installation? (y/N): " overwrite_confirm
    overwrite_confirm=${overwrite_confirm:-N}
    if [[ ! $overwrite_confirm =~ ^[Yy]$ ]]; then
        echo -e "❌ Aborting..."
        exit 1
    fi
    echo -e "🔧 Overwriting existing installation..."
    # Remove namespace and all resources inside it
    if kubectl delete namespace mgmtcompanion; then
        echo -e "✅ Existing installation removed successfully."
    else
        echo -e "❌ Error: Failed to remove existing installation."
        echo -e "💡 Tip: Manually remove the existing installation using 'kubectl delete namespace mgmtcompanion' and run the script again."
        exit 1
    fi
fi

# Install MgmtCompanion
echo -e "🔧 Installing MgmtCompanion..."
## Create namespace
if ! kubectl create namespace mgmtcompanion; then
    echo -e "❌ Error: Failed to create namespace mgmtcompanion."
    echo -e "💡 Tip: Check the logs above for any error messages."
    exit 1
fi
echo -e "✅ Namespace mgmtcompanion created successfully."

## Download the MgmtCompanion manifests (configmap, secret, statefulset)
echo -e "🔧 Downloading MgmtCompanion manifests..."
if ! curl -sSL https://management.umh.app/static/kubernetes/configmap.yaml -o /tmp/configmap.yaml; then
    echo -e "❌ Error: Failed to download configmap.yaml."
    echo -e "💡 Tip: Check your network connection"
    exit 1
fi
echo -e "✅ configmap.yaml downloaded successfully."
if ! curl -sSL https://management.umh.app/static/kubernetes/secret.yaml -o /tmp/secret.yaml; then
    echo -e "❌ Error: Failed to download secret.yaml."
    echo -e "💡 Tip: Check your network connection"
    exit 1
fi
echo -e "✅ secret.yaml downloaded successfully."
if ! curl -sSL https://management.umh.app/static/kubernetes/statefulset.yaml -o /tmp/statefulset.yaml; then
    echo -e "❌ Error: Failed to download statefulset.yaml."
    echo -e "💡 Tip: Check your network connection"
    exit 1
fi
echo -e "✅ statefulset.yaml downloaded successfully."
echo -e "✅ MgmtCompanion manifests downloaded successfully."

## Apply the MgmtCompanion manifests
echo -e "🔧 Applying MgmtCompanion manifests..."
if ! kubectl apply -f /tmp/configmap.yaml -n mgmtcompanion; then
    echo -e "❌ Error: Failed to apply configmap.yaml."
    echo -e "💡 Tip: Check the logs above for any error messages."
    exit 1
fi
echo -e "✅ configmap.yaml applied successfully."
if ! kubectl apply -f /tmp/secret.yaml -n mgmtcompanion; then
    echo -e "❌ Error: Failed to apply secret.yaml."
    echo -e "💡 Tip: Check the logs above for any error messages."
    exit 1
fi
echo -e "✅ secret.yaml applied successfully."
if ! kubectl apply -f /tmp/statefulset.yaml -n mgmtcompanion; then
    echo -e "❌ Error: Failed to apply statefulset.yaml."
    echo -e "💡 Tip: Check the logs above for any error messages."
    exit 1
fi
echo -e "✅ statefulset.yaml applied successfully."
echo -e "✅ MgmtCompanion manifests applied successfully."

## Wait a few seconds for the pod to start
echo -e "⏳ Waiting for the pod to start..."
sleep 5
echo -e "⌛ Checking for successful installation..."

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
    echo -e "🔄 Waiting for MgmtCompanion pod to be running..."
    while [[ $(kubectl get pod $mgmtcompanion_pod -n mgmtcompanion -o jsonpath='{.status.phase}') != "Running" && $ELAPSED -lt $TIMEOUT ]]; do
        echo -e "⏳ $ELAPSED seconds elapsed, timeout is $TIMEOUT seconds..."
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    if [[ $(kubectl get pod $mgmtcompanion_pod -n mgmtcompanion -o jsonpath='{.status.phase}') == "Running" ]]; then
        echo -e "✅ Installation successful."
    else
        echo -e "❌ Error: Installation failed - mgmtcompanion pod is not running."
        echo -e "💡 Tip: Check the pod's logs with 'kubectl logs $mgmtcompanion_pod -n mgmtcompanion' for more details."
        exit 1
    fi
else
    echo -e "❌ Error: Installation failed - Required resources are missing in the mgmtcompanion namespace."
    echo -e "💡 Tip: Verify the installation steps and ensure all necessary resources are created."
    exit 1
fi

echo -e "🎉 MgmtCompanion is installed successfully."