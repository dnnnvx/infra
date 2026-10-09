environment := "production"
context     := "homelab"

node-1 := "192.168.0.101"
# node-2 := "192.168.0.102"
node-3 := "192.168.0.103"
node-4 := "192.168.0.104"
nodes := node-1  + " " + node-3 + " " + node-4

# print available commands
default:
    @just --list

# enter dev shell (nix flake)
dev:
    nix develop --command zsh

# merge talosconfig from state into ~/.talos/config
add-talosconfig:
    tofu -chdir=tofu/{{ environment }} output -raw talosconfig > ~/.talos/config-{{ context }}
    talosctl config merge ~/.talos/config-{{ context }}
    rm ~/.talos/config-{{ context }}

# remove talosconfig context from ~/.talos/config
rm-talosconfig:
    yq -i 'del(.contexts.{{ context }})' ~/.talos/config
    @echo "Removed context '{{ context }}' from ~/.talos/config"

# merge kubeconfig from state into ~/.kube/config, rename context to cluster name
add-kubeconfig:
    tofu -chdir=tofu/{{ environment }} output -raw kubeconfig > ~/.kube/config-{{ context }}
    kubectl config --kubeconfig ~/.kube/config-{{ context }} rename-context admin@{{ context }} {{ context }}
    KUBECONFIG=~/.kube/config:~/.kube/config-{{ context }} kubectl config view --flatten > ~/.kube/config-merged
    mv ~/.kube/config-merged ~/.kube/config
    rm ~/.kube/config-{{ context }}

# remove kubeconfig context from ~/.kube/config
rm-kubeconfig:
    kubectl config delete-context {{ context }} || true
    kubectl config delete-cluster {{ context }} || true
    kubectl config delete-user admin@{{ context }} || true
    @echo "Removed context '{{ context }}' from ~/.kube/config"

# apply and upgrade node images (needs machine full reboot)
upgrade-nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    IMAGE=$(cd tofu/{{ environment }} && tofu output -raw installer_image)
    for node in {{ nodes }}; do
      echo "Upgrading $node..."
      talosctl --context {{ context }} -n "$node" upgrade --image "$IMAGE" --wait
      echo "$node upgraded, waiting for health..."
      sleep 10
    done

# encrypt a secret file in-place with sops
encrypt file:
    #!/usr/bin/env bash
    echo -n "Age private key: "
    read -rs SOPS_AGE_KEY
    echo
    export SOPS_AGE_KEY
    sops --encrypt --in-place {{ file }}

# edit an encrypted secret
edit-secret file:
    #!/usr/bin/env bash
    echo -n "Age private key: "
    read -rs SOPS_AGE_KEY
    echo
    export SOPS_AGE_KEY
    sops {{ file }}

# build and serve docs
docs:
    mdbook serve docs --port 3000

# sync flux with the defined git repo
sync:
    flux reconcile source git flux-system -n flux-system --context {{ context }}
    flux reconcile kustomization infrastructure
    flux reconcile kustomization config
    flux reconcile kustomization apps

# rewrite pinned versions in-place to the latest available, then show the diff
updates:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "Working tree is dirty — commit or stash first, so the diff below is only Renovate's."
      exit 1
    fi
    # local platform edits files but never branches or pushes; review, then commit
    RENOVATE_GITHUB_COM_TOKEN=$(gh auth token) LOG_LEVEL=info renovate --platform=local --dry-run=false
    echo
    if git diff --quiet; then
      echo "Everything is up to date."
    else
      git --no-pager diff --stat
      echo
      echo "Review with 'git diff', then 'just validate' before committing."
    fi

# validate all kustomize overlays and manifests
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    errors=0

    overlays=$(find apps -path "*/overlays/*" -maxdepth 4 -name "kustomization.yaml" -exec dirname {} \; | sort)
    for dir in clusters/{{ environment }} infrastructure config $overlays; do
      echo "==> Building $dir..."
      output=$(kustomize build "$dir" 2>&1) || {
        echo "    ✗ kustomize build FAILED:"
        echo "$output"
        errors=$((errors + 1))
        echo
        continue
      }
      echo "    ✓ kustomize build OK"
      echo "==> Validating $dir manifests..."
      if echo "$output" | yq 'select(.kind != "Secret")' | kubeconform -strict -ignore-missing-schemas -summary 2>&1 | sed 's/^/    /'; then
        echo "    ✓ kubeconform OK"
      else
        errors=$((errors + 1))
      fi
      echo
    done

    if [ $errors -gt 0 ]; then
      echo "FAILED: $errors error(s) found"
      exit 1
    fi
    echo "All checks passed!"
