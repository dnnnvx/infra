cluster := "homelab"

node-1 := "192.168.0.101"
node-2 := "192.168.0.102"
node-3 := "192.168.0.103"
node-4 := "192.168.0.104"
nodes := node-1 + " " + node-2 + " " + node-3 + " " + node-4

# merge talosconfig from state into ~/.talos/config
add-talosconfig:
  tofu -chdir=clusters/{{cluster}} output -raw talosconfig > ~/.talos/config-{{cluster}}
  talosctl config merge ~/.talos/config-{{cluster}}
  rm ~/.talos/config-{{cluster}}

# remove talosconfig context from ~/.talos/config
rm-talosconfig:
  yq -i 'del(.contexts.{{cluster}})' ~/.talos/config
  @echo "Removed context '{{cluster}}' from ~/.talos/config"

# merge kubeconfig from state into ~/.kube/config, rename context to cluster name
add-kubeconfig:
  tofu -chdir=clusters/{{cluster}} output -raw kubeconfig > ~/.kube/config-{{cluster}}
  kubectl config --kubeconfig ~/.kube/config-{{cluster}} rename-context admin@{{cluster}} {{cluster}}
  KUBECONFIG=~/.kube/config:~/.kube/config-{{cluster}} kubectl config view --flatten > ~/.kube/config-merged
  mv ~/.kube/config-merged ~/.kube/config
  rm ~/.kube/config-{{cluster}}

# remove kubeconfig context/cluster/user from ~/.kube/config
rm-kubeconfig:
  kubectl config delete-context {{cluster}} || true
  kubectl config delete-cluster {{cluster}} || true
  kubectl config delete-user admin@{{cluster}} || true
  @echo "Removed context '{{cluster}}' from ~/.kube/config"

upgrade-nodes:
  #!/usr/bin/env bash
  IMAGE=$(cd clusters/{{cluster}} && tofu output -raw installer_image)
  for node in {{nodes}}; do
    echo "Upgrading $node..."
    talosctl -n $node upgrade --image "$IMAGE" --wait
    echo "$node upgraded, waiting for health..."
    sleep 10
  done

sync:
  flux reconcile source git flux-system -n flux-system --context {{cluster}}
