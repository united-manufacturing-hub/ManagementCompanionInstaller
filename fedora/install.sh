#!/bin/bash

# Customizable Parameters
export INSTALL_K3S_VERSION=v1.28.2+k3s1
export INSTALL_KUBECTL_VERSION=v1.28.2
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export MANAGEMENT_URL=https://management.umh.app
export API_URL=$MANAGEMENT_URL/api
export CONFIGMAP_URL=$MANAGEMENT_URL/kubernetes/configmap.yaml
export SECRET_URL=$MANAGEMENT_URL/kubernetes/secret.yaml
export STATEFULSET_URL=$MANAGEMENT_URL/kubernetes/statefulset.yaml
export INSTALLER_URL=$MANAGEMENT_URL/fedora/install.sh
export IMAGE_VERSION=latest
TIMEOUT=60  # 1 minute
INTERVAL=5   # check every 5 seconds


function logMessage {
    local emoji=$1
    local message=$2
    echo -e "$emoji $message" | tee -a /tmp/mgmt_install.log
}

function handleError {
    logMessage "❌ Error:" "$1"
    logMessage "💡 Tip:" "$2"
    logMessage " For more details, check the logs at /tmp/mgmt_install.log"

    # Prompt user if they want to display the log file contents
    read -p "Do you want to display the log file contents? (Y/n): " display_log
    display_log=${display_log:-Y}
    if [[ $display_log =~ ^[Yy]$ ]]; then
        cat /tmp/mgmt_install.log
    fi

    exit 1
}


function handleSuccess {
    logMessage "  ✅" "$1"
}

function handleStep {
    logMessage "🔧" "$1"
}

function handleCheck {
    logMessage "🔍" "$1"
}

function handleWarning {
    logMessage "⚠️" "$1"
}

function handleSleep {
    logMessage "⏳" "$1"
    sleep $2
}

function handleSecurity {
    logMessage "🔓" "$1"
}

function handleInstalled {
    logMessage "🎉" "$1"
}

# Define a function to check pod readiness
function check_pod_readiness {
    local pod_name=$1
    local namespace=$2
    kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"
}

rm -f /tmp/mgmt_install.log
rn -f /tmp/configmap.yaml
rm -f /tmp/secret.yaml
rm -f /tmp/statefulset.yaml
clear

# Override API_URL if CUSTOM_API_URL is set
if [[ -n $CUSTOM_API_URL ]]; then
    export MANAGEMENT_URL=$CUSTOM_API_URL
    export API_URL=$MANAGEMENT_URL/api
    export CONFIGMAP_URL=$MANAGEMENT_URL/kubernetes/configmap.yaml
    export SECRET_URL=$MANAGEMENT_URL/kubernetes/secret.yaml
    export STATEFULSET_URL=$MANAGEMENT_URL/kubernetes/statefulset.yaml
    export INSTALLER_URL=$MANAGEMENT_URL/fedora/install.sh
    echo "MANAGEMENT_URL: $MANAGEMENT_URL"
    echo "API_URL: $API_URL"
    echo "CONFIGMAP_URL: $CONFIGMAP_URL"
    echo "SECRET_URL: $SECRET_URL"
    echo "STATEFULSET_URL: $STATEFULSET_URL"
    echo "INSTALLER_URL: $INSTALLER_URL"
fi

# Overwrite IMAGE_VERSION if CUSTOM_IMAGE_VERSION is set
if [[ -n $CUSTOM_IMAGE_VERSION ]]; then
    export IMAGE_VERSION=$CUSTOM_IMAGE_VERSION
    echo "IMAGE_VERSION: $IMAGE_VERSION"
fi


# Summary of changes to be done #600
handleCheck "This script will perform the following actions on your system:"
echo -e "1️⃣ Check for necessary prerequisites."
echo -e "2️⃣ Install k3s and kubectl if not already installed."
echo -e "3️⃣ Disable the firewall (as per k3s documentation for RHEL/CentOS/Fedora)."
echo -e "4️⃣ Install or overwrite MgmtCompanion."

# Ask user for confirmation
read -p "Do you want to continue? (Y/n): " confirm
confirm=${confirm:-Y}
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    handleError "Aborting..." "You can run the script again to install MgmtCompanion."
    exit 1
fi
handleStep "Beginning installation..."

# The install script shall check if executed as root user, and abort if not #572
handleCheck "Checking for root..."
if [[ $EUID -ne 0 ]]; then
    handleError "This script must be run as root." "Use 'sudo ./scriptname.sh' to run it as root or use the following command: curl -sSL $INSTALLER_URL | AUTH_TOKEN=<instance-installation-token> sudo -E bash"
fi
handleSuccess "Root user detected."

# Check if the RHEL machine is registered
handleCheck "Checking if your RHEL machine is registered..."
if ! subscription-manager status >> /tmp/mgmt_install.log 2>&1; then
    handleError "Your RHEL machine is not registered." "Register your machine with 'subscription-manager register' and run the script again."
    exit 1
fi
handleSuccess "Your RHEL machine is registered."

# Check RHEL version
handleCheck "Checking RHEL version..."
RHEL_VERSION=$(grep -oP '(?<= )[0-9]+(?=\.?)' /etc/redhat-release | head -1)
if [[ ! "$RHEL_VERSION" =~ ^(7|8|9)$ ]]; then
    handleError "Unsupported RHEL version. Supported versions are 7, 8, and 9." "Check your RHEL version with 'cat /etc/redhat-release' and upgrade to a supported version."
    exit 1
fi
handleSuccess "RHEL version $RHEL_VERSION is supported."

# The install script shall check if the authentication token is present #574
handleCheck "Checking for authentication token..."
if [[ -z "$AUTH_TOKEN" ]]; then
    handleError "Authentication token is not present." "Ensure you've included the AUTH_TOKEN in your command. Example: curl -sSL $INSTALLER_URL | AUTH_TOKEN=<instance-installation-token> sudo -E bash"
fi
handleSuccess "Authentication token detected."

# The install script shall check if there is a internet connection to $MANAGEMENT_URL #573
handleCheck "Checking for dig..."
if ! command -v dig >> /tmp/mgmt_install.log 2>&1; then
    handleStep "dig is not installed. Installing dig..."
    if ! yum install -y bind-utils >> /tmp/mgmt_install.log 2>&1; then
        handleError "Failed to install dig." "Check your network connection or install dig manually using 'sudo yum install bind-utils' and run the script again."
        exit 1
    fi
fi
handleSuccess "dig is installed successfully."
handleCheck "Checking for internet connection..."
## Check if $MANAGEMENT_URL is resolvable (dns)
handleStep "Checking if $MANAGEMENT_URL is resolvable..."
if ! dig +short $MANAGEMENT_URL >> /tmp/mgmt_install.log 2>&1; then
    handleError "$MANAGEMENT_URL is not resolvable." "Check your network connection or try again later."
    exit 1
fi
## Check if $MANAGEMENT_URL is reachable (http)
handleStep "Checking if $MANAGEMENT_URL is reachable..."
if ! curl -sSL $API_URL >> /tmp/mgmt_install.log 2>&1; then
    handleError "$MANAGEMENT_URL is not reachable." "Check your network connection or try again later."
    exit 1
fi
handleSuccess "$MANAGEMENT_URL is resolvable."

# Validate AUTH_TOKEN format
handleCheck "Validating authentication token format..."
if [[ ! "$AUTH_TOKEN" =~ ^[a-fA-F0-9]{64}$ ]]; then
    handleError "Invalid authentication token format." "Ensure your authentication token is a 256-bit hex-encoded string."
    exit 1
fi
handleSuccess "Authentication token format is valid."

# Ensure curl is installed (this should never happen, as we use curl to download the script, but just in case)
handleCheck "Checking for curl..."
if ! command -v curl >> /tmp/mgmt_install.log 2>&1; then
    handleStep "curl is not installed. Installing curl..."
    if ! yum install -y curl; then
        handleError "Failed to install curl." "Check your network connection or install curl manually using 'sudo yum install curl' and run the script again."
        exit 1
    fi
fi
handleSuccess "curl is installed successfully."

# Ensure /usr/local/bin is in the PATH
handleCheck "Checking if /usr/local/bin is in the PATH..."
if [[ ! ":$PATH:" == *":/usr/local/bin:"* ]]; then
    handleStep "/usr/local/bin is not in the PATH. Adding it to the PATH..."
    if ! echo "export PATH=$PATH:/usr/local/bin" >> ~/.bashrc; then
        handleError "Failed to add /usr/local/bin to the PATH." "Manually add /usr/local/bin to the PATH using 'echo \"export PATH=\$PATH:/usr/local/bin\" >> ~/.bashrc' and run the script again."
        exit 1
    fi
    handleSuccess "/usr/local/bin is added to the PATH successfully."
else
    handleSuccess "/usr/local/bin is already in the PATH."
fi

# Source the .bashrc file to update the PATH
handleCheck "Sourcing the .bashrc file..."
source ~/.bashrc

# Check if SELinux is enabled
handleCheck "Checking if SELinux is enabled..."
if getenforce | grep -Fq 'Enforcing'; then
    # Install SELinux policy for k3s ( container-selinux selinux-policy-base)
    handleStep "SELinux is enabled. Installing SELinux policy for k3s..."
    if ! yum install -y container-selinux selinux-policy-base >> /tmp/mgmt_install.log 2>&1; then
        handleError "Failed to install SELinux policy for k3s." "Check your network connection or install SELinux policy for k3s manually using 'sudo yum install -y container-selinux selinux-policy-base' and run the script again."
        exit 1
    fi
    handleSuccess "SELinux policy (1/2) for k3s is installed successfully."
    handleStep "Installing SELinux policy (2/2) for k3s..."
    # This step requires allowing SHA1 package signatures
    handleStep "Allowing SHA1 package signatures..."
    if ! update-crypto-policies --set DEFAULT:SHA1 >> /tmp/mgmt_install.log 2>&1; then
        handleError "Failed to allow SHA1 package signatures." "Manually allow SHA1 package signatures using 'sudo update-crypto-policies --set DEFAULT:SHA1' and run the script again."
        exit 1
    fi
    handleSuccess "SHA1 package signatures are allowed."
    if ! yum install -y https://rpm.rancher.io/k3s/latest/common/centos/7/noarch/k3s-selinux-0.2-1.el7_8.noarch.rpm >> /tmp/mgmt_install.log 2>&1; then
        handleError "Failed to install SELinux policy for k3s." "Check your network connection or install SELinux policy for k3s manually using 'sudo yum install -y https://rpm.rancher.io/k3s/latest/common/centos/7/noarch/k3s-selinux-0.2-1.el7_8.noarch.rpm' and run the script again."
        exit 1
    fi
    # Return back to the default crypto policy
    handleStep "Returning back to the default crypto policy..."
    if ! update-crypto-policies --set DEFAULT >> /tmp/mgmt_install.log 2>&1; then
        handleError "Failed to return back to the default crypto policy." "Manually return back to the default crypto policy using 'sudo update-crypto-policies --set DEFAULT' and run the script again."
        exit 1
    fi
    handleSuccess "SELinux policy (2/2) for k3s is installed successfully."
else
    handleSuccess "SELinux is disabled."
fi
handleSuccess "SELinux policy for k3s is installed successfully."

# Disable nm-cloud-setup.service
handleCheck "Checking if nm-cloud-setup.service is enabled..."
if systemctl list-units --full --all | grep -Fq 'nm-cloud-setup.service'; then
    handleStep "nm-cloud-setup.service is enabled. Disabling nm-cloud-setup.service..."
    if ! systemctl disable --now nm-cloud-setup.service >> /tmp/mgmt_install.log 2>&1; then
        handleError "Failed to disable nm-cloud-setup.service." "Manually disable nm-cloud-setup.service using 'sudo systemctl disable --now nm-cloud-setup.service' and run the script again."
        exit 1
    fi
    handleSuccess "nm-cloud-setup.service is disabled successfully."
else
    handleSuccess "nm-cloud-setup.service is already disabled."
fi

# The install script shall check if k3s is installed, and if not install it #575
handleCheck "Checking for k3s..."
if ! command -v k3s >> /tmp/mgmt_install.log 2>&1; then
    handleStep "k3s is not installed. Installing k3s..."
    curl -sSL https://get.k3s.io -o k3s-install.sh >> /tmp/mgmt_install.log 2>&1
    if [[ $? -ne 0 ]]; then
        handleError "Failed to download k3s-install.sh." "Check your network connection or download k3s-install.sh & install manually from https://get.k3s.io and run the script again."
        exit 1
    fi
    chmod +x k3s-install.sh
    if ! bash k3s-install.sh >> /tmp/mgmt_install.log 2>&1; then
        handleError "Failed to install k3s." "Check the logs above for any error messages."
        exit 1
    fi
    rm k3s-install.sh
    handleSuccess "k3s is installed successfully."
else
    handleSuccess "k3s is already installed."
fi

# The install script shall check if kubectl is installed or install it #576
handleCheck "Checking for kubectl..."
if ! command -v kubectl >> /tmp/mgmt_install.log 2>&1; then
    handleStep "kubectl is not installed. Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$INSTALL_KUBECTL_VERSION/bin/linux/amd64/kubectl" -o kubectl >> /tmp/mgmt_install.log 2>&1
    if [[ $? -ne 0 ]]; then
        handleError "Failed to download kubectl." "Check your network connection or download kubectl manually from https://dl.k8s.io/release/$INSTALL_KUBECTL_VERSION/bin/linux/amd64/kubectl, make it executable, and move it to /usr/local/bin/ and run the script again or install kubectl manually using 'sudo yum install kubectl' and run the script again."
        exit 1
    fi
    mv kubectl /usr/local/bin/
    chmod +x /usr/local/bin/kubectl
    handleSuccess "kubectl is installed successfully."
else
    handleSuccess "kubectl is already installed."
fi

# The install script shall disable the firewall for RHEL/CentOS/Fedora as per k3s documentation
handleSecurity "Checking and disabling the firewall..."
if systemctl list-units --full --all | grep -Fq 'firewalld.service'; then
    if ! systemctl disable --now firewalld; then
        handleError "Failed to disable the firewall." "Manually disable the firewall using 'sudo systemctl disable --now firewalld' and run the script again."
        exit 1
    fi
    handleSuccess "Firewall disabled successfully."
else
    handleWarning "Firewalld service not found. Skipping firewall disable step."
fi
handleSuccess "Firewall disabled successfully."

# The install script shall detect if MgmgCompanion is already installed #577
handleCheck "Checking for existing MgmtCompanion installation..."
if kubectl get namespace mgmtcompanion >> /tmp/mgmt_install.log 2>&1; then
    handleWarning "MgmtCompanion is already installed."

    # If the install script detects an existing MgmtCompanion installation it shall ask the user if he wants to overwrite or abort #578
    read -p "Do you want to overwrite the existing installation? (y/N): " overwrite_confirm
    overwrite_confirm=${overwrite_confirm:-N}
    if [[ ! $overwrite_confirm =~ ^[Yy]$ ]]; then
        handleError "Aborting..." "You can run the script again to install MgmtCompanion."
        exit 1
    fi
    handleStep "Overwriting existing installation..."
    # Remove namespace and all resources inside it
    if kubectl delete namespace mgmtcompanion; then
        handleSuccess "Existing installation removed successfully."
    else
        handleError "Failed to remove existing installation." "Manually remove the existing installation using 'kubectl delete namespace mgmtcompanion' and run the script again."
        exit 1
    fi
fi

# Install MgmtCompanion
handleStep "Installing MgmtCompanion..."
## Create namespace
if ! kubectl create namespace mgmtcompanion; then
    handleError "Failed to create namespace mgmtcompanion." "Check the logs above for any error messages."
    exit 1
fi
handleSuccess "Namespace mgmtcompanion created successfully."

## Download the MgmtCompanion manifests (configmap, secret, statefulset)
handleStep "Downloading MgmtCompanion manifests..."
if ! curl -sSL $CONFIGMAP_URL -o /tmp/configmap.yaml >> /tmp/mgmt_install.log 2>&1; then
    handleError "Failed to download configmap.yaml." "Check your network connection"
    exit 1
fi
handleSuccess "configmap.yaml downloaded successfully."
if ! curl -sSL $SECRET_URL -o /tmp/secret.yaml >> /tmp/mgmt_install.log 2>&1; then
    handleError "Failed to download secret.yaml." "Check your network connection"
    exit 1
fi
handleSuccess "secret.yaml downloaded successfully."
if ! curl -sSL $STATEFULSET_URL -o /tmp/statefulset.yaml >> /tmp/mgmt_install.log 2>&1; then
    handleError "Failed to download statefulset.yaml." "Check your network connection"
    exit 1
fi
handleSuccess "statefulset.yaml downloaded successfully."
handleSuccess "MgmtCompanion manifests downloaded successfully."

# Encode the AUTH_TOKEN to base64 as Kubernetes secrets require base64 encoded values
handleStep "Encoding the authentication token..."
encoded_auth_token=$(echo -n "$AUTH_TOKEN" | base64)
# Replace the auth-token value in the downloaded secret.yaml file
sed -i "s/auth-token: \"null\"/auth-token: \"$encoded_auth_token\"/" /tmp/secret.yaml
handleSuccess "Authentication token encoded successfully."

## Apply the MgmtCompanion manifests
handleStep "Applying MgmtCompanion manifests..."
if ! kubectl apply -f /tmp/configmap.yaml -n mgmtcompanion; then
    handleError "Failed to apply configmap.yaml." "Check the logs above for any error messages."
    exit 1
fi
handleSuccess "configmap.yaml applied successfully."
if ! kubectl apply -f /tmp/secret.yaml -n mgmtcompanion; then
    handleError "Failed to apply secret.yaml." "Check the logs above for any error messages."
    exit 1
fi
handleSuccess "secret.yaml applied successfully."
# Use sed to replace the image version in statefulset.yaml (placeholder is __VERSION__)
sed -i "s/__VERSION__/$IMAGE_VERSION/g" /tmp/statefulset.yaml
if ! kubectl apply -f /tmp/statefulset.yaml -n mgmtcompanion; then
    handleError "Failed to apply statefulset.yaml." "Check the logs above for any error messages."
    exit 1
fi
handleSuccess "statefulset.yaml applied successfully."
handleSuccess "MgmtCompanion manifests applied successfully."

## Wait a few seconds for the pod to start
handleSleep "Waiting for kubernetes to finalize the installation..." 5

# Check for successful installation by querying k3s to check if the following is true (all resources are inside the mgmtcompanion namespace)
# - statefulset: mgmtcompanion
# - secret: mgmtcompanion-secret
# - configmap: mgmtcompanion-config
if [[ $(kubectl get statefulsets -n mgmtcompanion --field-selector metadata.name=mgmtcompanion -o jsonpath='{.items[*].metadata.name}') == "mgmtcompanion" ]] &&
   [[ $(kubectl get secrets -n mgmtcompanion --field-selector metadata.name=mgmtcompanion-secret -o jsonpath='{.items[*].metadata.name}') == "mgmtcompanion-secret" ]] &&
   [[ $(kubectl get configmaps -n mgmtcompanion --field-selector metadata.name=mgmtcompanion-config -o jsonpath='{.items[*].metadata.name}') == "mgmtcompanion-config" ]]; then
    mgmtcompanion_pod=$(kubectl get pods -n mgmtcompanion --selector=statefulset.kubernetes.io/pod-name=mgmtcompanion-0 -o jsonpath='{.items[*].metadata.name}')
    ELAPSED=0
    handleSleep "Waiting for MgmtCompanion pod ($mgmtcompanion_pod) to be running and ready..." 5
    while ! check_pod_readiness $mgmtcompanion_pod mgmtcompanion && [ $ELAPSED -lt $TIMEOUT ]; do
        handleSleep "Waiting for MgmtCompanion pod to be ready..." $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done

    # If pod is not ready within 1 minute, show the container logs
    if ! check_pod_readiness $mgmtcompanion_pod mgmtcompanion; then
        handleWarning "MgmtCompanion pod is not ready within 1 minute. Displaying container logs..."
        kubectl logs $mgmtcompanion_pod -n mgmtcompanion --all-containers
        exit 1
    fi

    handleSuccess "Installation successful."
else
    handleError "Installation failed - Required resources are missing in the mgmtcompanion namespace." "Verify the installation steps and ensure all necessary resources are created."
    exit 1
fi
handleInstalled "MgmtCompanion is installed successfully."