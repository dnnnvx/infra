export CLUSTER_NAME=ilposto
export API_ENDPOINT="https://192.168.1.100:6443"
export NODE_NAME=nuc-3

talosctl gen secrets --output-file secrets.yaml

talosctl gen config  \
    --with-secrets secrets.yaml \
    --output-types talosconfig  \
    --output talosconfig.yaml   \
    $CLUSTER_NAME \
    $API_ENDPOINT

talosctl config merge ./talosconfig.yaml

talosctl gen config \
    --output rendered/$NODE_NAME.yaml                         \
    --output-types controlplane                               \
    --with-cluster-discovery=false                            \
    --with-secrets secrets.yaml                               \
    --config-patch @patches/talos-image.yaml                  \
    --config-patch @patches/networking.yaml                   \
    --config-patch @patches/allow-controlplane-workloads.yaml \
    --config-patch @patches/disable-default-cni.yaml          \
    --config-patch @patches/tailscale-auth.yaml               \
    --config-patch @nodes/$NODE_NAME.yaml                     \
    $CLUSTER_NAME                                             \
    $API_ENDPOINT

talosctl --nodes 192.168.1.101 apply-config --file rendered/nuc-1.yaml --insecure
talosctl --nodes 192.168.1.102 apply-config --file rendered/nuc-2.yaml --insecure
talosctl --nodes 192.168.1.103 apply-config --file rendered/nuc-3.yaml --insecure

# edit ~/.talos/config and replace 127.0.0.1 with 192.168.1.101
talosctl -n 192.168.1.103 dashboard

talosctl -n 192.168.1.102 reboot # it will reboot automatically, but just in case...

talosctl -n 192.168.1.103 kubeconfig # only on first control-plane
talosctl -n 192.168.1.103 bootstrap # only on first control-plane

export KUBERNETES_API_SERVER_ADDRESS=192.168.1.100
export KUBERNETES_API_SERVER_PORT=6443

helm repo add cilium https://helm.cilium.io/
helm install                                                    \
    cilium                                                      \
    cilium/cilium                                               \
    --version 1.15.0                                            \
    --namespace kube-system                                     \
    --set kubeProxyReplacement=disabled                         \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set ipam.mode=kubernetes                                  \
    --set hostFirewall.enabled=true                             \
    --set hubble.relay.enabled=true                             \
    --set hubble.ui.enabled=true                                \
    --set cgroup.autoMount.enabled=false                        \
    --set cgroup.hostRoot=/sys/fs/cgroup                        \
    --set k8sServiceHost="${KUBERNETES_API_SERVER_ADDRESS}"     \
    --set k8sServicePort="${KUBERNETES_API_SERVER_PORT}"

# Flux

export GITHUB_TOKEN=$GITHUB_TOKEN
export GITHUB_USER=dnnnvx
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=ilposto-infra \
  --branch=main \
  --path=./clusters/main \
  --personal

# sops

gpg --expert --full-generate-key
ssh-keygen -t ed25519 -C "marco@ilposto.studio"
gpg --export-secret-keys --armor "6B960E729E05C93E5C7FAD360F5213C262342832" |
  kubectl create secret generic sops-gpg \
  --namespace=flux-system \
  --from-file=sops.asc=/dev/stdin --dry-run=client -o yaml > clusters/main/flux-system/sops.yaml
gpg --export --armor "6B960E729E05C93E5C7FAD360F5213C262342832" > .flux.pub.asc
