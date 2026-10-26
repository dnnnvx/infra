environment := "production"
context     := "homelab"

node-1 := "192.168.0.101"
# node-2 := "192.168.0.102"
node-3 := "192.168.0.103"
node-4 := "192.168.0.104"
nodes := node-1  + " " + node-3 + " " + node-4

# age private key for sops (keep it 0600). Explicit because sops' default on macOS is ~/Library/Application Support
export SOPS_AGE_KEY_FILE := env("SOPS_AGE_KEY_FILE", home_directory() + "/.config/sops/age/keys.txt")

# print available commands
default:
    @just --list

# enter dev shell (nix flake)
dev:
    nix develop --command zsh

# merge talosconfig from state into ~/.talos/config
add-talosconfig:
    just tofu output -raw talosconfig > ~/.talos/config-{{ context }}
    talosctl config merge ~/.talos/config-{{ context }}
    rm ~/.talos/config-{{ context }}

# remove talosconfig context from ~/.talos/config
rm-talosconfig:
    yq -i 'del(.contexts.{{ context }})' ~/.talos/config
    @echo "Removed context '{{ context }}' from ~/.talos/config"

# merge kubeconfig from state into ~/.kube/config, rename context to cluster name
add-kubeconfig:
    just tofu output -raw kubeconfig > ~/.kube/config-{{ context }}
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
    IMAGE=$(just tofu output -raw installer_image)
    for node in {{ nodes }}; do
      echo "Upgrading $node..."
      talosctl --context {{ context }} -n "$node" upgrade --image "$IMAGE" --wait
      echo "$node upgraded, waiting for health..."
      sleep 10
    done

# run tofu with the R2 keys and variables from infrastructure/tofu/secret.yaml: just tofu plan
tofu *args:
    #!/usr/bin/env bash
    set -euo pipefail
    # Decrypted in memory only. terraform.tfvars (HCL) -> TF_VAR_<name>: strings as-is,
    # maps/objects as JSON, which tofu parses as HCL (so ${ and %{ are escaped).
    secret=$(sops --decrypt infrastructure/tofu/secret.yaml)
    eval "$(printf '%s\n' "$secret" | yq -r '.stringData | (
      "export AWS_ACCESS_KEY_ID=" + (.AWS_ACCESS_KEY_ID | @sh),
      "export AWS_SECRET_ACCESS_KEY=" + (.AWS_SECRET_ACCESS_KEY | @sh))')"
    eval "$(printf '%s\n' "$secret" | yq -r '.stringData."terraform.tfvars"' | yq -p hcl -o json | yq -p json -r '
      to_entries[] | "export TF_VAR_" + .key + "=" + ((
        if (.value | tag) == "!!str" then .value
        else .value | to_json(0) | sub("\\$\\{"; "$$$${") | sub("%\\{"; "%%{") end
      ) | @sh)')"
    unset secret
    tofu -chdir=tofu/{{ environment }} {{ args }}

# encrypt a secret file in-place with sops (needs only the public key in .sops.yaml)
encrypt file:
    sops --encrypt --in-place {{ file }}

# edit an encrypted secret, e.g. the tofu inputs: just edit-secret infrastructure/tofu/secret.yaml
edit-secret file:
    sops {{ file }}

# build and serve docs
docs:
    mdbook serve docs --port 3000

# sync flux with the defined git repo
sync:
    flux reconcile kustomization flux-system --with-source --context {{ context }}
    flux reconcile kustomization infrastructure
    flux reconcile kustomization config
    kustomize build clusters/production/apps | yq '.metadata.name' | grep -v '^---$' | xargs -n1 flux reconcile kustomization

# replay a signed Tangled push webhook (no commit needed): just ci-build <clone_url> <sha> [repo]
ci-build clone_url sha repo="web":
    #!/usr/bin/env bash
    set -euo pipefail
    secret=$(kubectl --context {{ context }} -n tekton-pipelines get secret tangled-webhook -o jsonpath='{.data.secret}' | base64 -d | tr -d '\n')
    body=$(jq -nc --arg sha '{{ sha }}' --arg url '{{ clone_url }}' --arg repo '{{ repo }}' \
      '{ref: "refs/heads/main", after: $sha, repository: {name: $repo, clone_url: $url}}')
    sig=sha256=$(printf %s "$body" | openssl dgst -sha256 -hmac "$secret" -hex | awk '{print $NF}')
    curl -sS -w '\nHTTP %{http_code}\n' -X POST https://ci.casasulgorgo.net/ \
      -H 'Content-Type: application/json' -H 'X-Tangled-Event: push' -H "X-Tangled-Signature-256: $sig" -d "$body"
    echo "watch: kubectl -n tekton-ci get pipelinerun -w"

# rewrite pinned versions in-place to the latest available, then show the diff
renovate:
    #!/usr/bin/env bash
    set -euo pipefail
    RENOVATE_GITHUB_COM_TOKEN=$(gh auth token) LOG_LEVEL=debug LOG_FORMAT=json renovate --platform=local 2>/dev/null > /tmp/renovate.json
    jq -r 'select(.msg=="packageFiles with updates")
      | .config | to_entries[] | .value[]
      | .packageFile as $f | .deps[] | select((.updates|length)>0)
      | . as $d | .updates[]
      | [$f, $d.depName, $d.currentValue, .newValue, .updateType] | @tsv' \
      /tmp/renovate.json | column -t

# validate the Flux entrypoints and every app (including disabled and CI-built ones)
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    errors=0

    for dir in clusters/{{ environment }} infrastructure/controllers infrastructure/configs apps/*/; do
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
