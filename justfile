cluster := "homelab"

# merge talosconfig from state into ~/.talos/config
add-talosconfig:
    tofu -chdir=clusters/{{cluster}} output -raw talosconfig > ~/.talos/config-{{cluster}}
    talosctl config merge ~/.talos/config-{{cluster}}
    rm ~/.talos/config-{{cluster}}

# remove talosconfig context from ~/.talos/config
rm-talosconfig:
    yq -i 'del(.contexts.{{cluster}})' ~/.talos/config
    @echo "Removed context '{{cluster}}' from ~/.talos/config"

# merge kubeconfig from state into ~/.kube/config
add-kubeconfig:
    tofu -chdir=clusters/{{cluster}} output -raw kubeconfig > ~/.kube/config-{{cluster}}
    KUBECONFIG=~/.kube/config:~/.kube/config-{{cluster}} kubectl config view --flatten > ~/.kube/config-merged
    mv ~/.kube/config-merged ~/.kube/config
    rm ~/.kube/config-{{cluster}}

# remove kubeconfig context/cluster/user from ~/.kube/config
rm-kubeconfig:
    kubectl config delete-context {{cluster}} || true
    kubectl config delete-cluster {{cluster}} || true
    kubectl config delete-user admin@{{cluster}} || true
    @echo "Removed context '{{cluster}}' from ~/.kube/config"
