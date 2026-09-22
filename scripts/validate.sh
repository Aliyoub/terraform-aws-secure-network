#!/usr/bin/env bash
# Contrôles locaux avant commit. Aucun appel AWS, aucune ressource créée.
#
#   1. formatage Terraform (fmt -check)
#   2. initialisation sans backend, puis validation (validate)
#   3. analyse statique (tflint, si installé)
#   4. garde-fou de coût (aucune ressource payante déclarée)
#   5. recherche de secrets et de fichiers sensibles suivis par Git
#
# Usage : scripts/validate.sh
set -euo pipefail

cd "$(dirname "$0")/.."
root="$(pwd)"
failures=0

# Chaque environnement (dev, bootstrap, ...) est un module racine indépendant,
# avec son propre state : tous doivent être validés.
env_dirs=(terraform/environments/*/)

step() { printf '\n== %s ==\n' "$1"; }
fail() { printf 'ÉCHEC : %s\n' "$1" >&2; failures=$((failures + 1)); }

step "1/5 terraform fmt -check"
if terraform fmt -check -recursive -diff terraform; then
  echo "OK"
else
  fail "formatage incorrect (corriger avec : terraform fmt -recursive terraform)"
fi

step "2/5 terraform init (sans backend) et validate"
for env_dir in "${env_dirs[@]}"; do
  echo "-- $env_dir --"
  if (cd "$env_dir" && terraform init -backend=false -input=false -no-color >/dev/null \
      && terraform validate -no-color); then
    :
  else
    fail "terraform init ou validate a échoué pour $env_dir"
  fi
done

step "3/5 tflint"
if command -v tflint >/dev/null 2>&1; then
  tflint --init >/dev/null
  for env_dir in "${env_dirs[@]}"; do
    echo "-- $env_dir --"
    if (cd "$env_dir" && tflint --config="$root/.tflint.hcl"); then
      echo "OK"
    else
      fail "tflint a signalé des problèmes pour $env_dir"
    fi
  done
else
  echo "tflint non installé : étape ignorée (non vérifié)."
fi

step "4/5 garde-fou de coût"
if ! scripts/check-aws-cost-risk.sh; then
  fail "ressource potentiellement payante déclarée"
fi

step "5/5 secrets et fichiers sensibles suivis par Git"
sensitive_files=$(git ls-files | grep -E '(\.tfstate(\.|$)|\.tfvars$|\.tfvars\.json$|\.pem$|\.key$|(^|/)\.env)' || true)
if [[ -n "$sensitive_files" ]]; then
  echo "$sensitive_files" | sed 's/^/  /'
  fail "fichiers sensibles suivis par Git"
fi

# Motifs : clé d'accès AWS, clé secrète AWS, clé privée. Ce script est exclu de l'analyse.
secret_pattern='AKIA[0-9A-Z]{16}|aws_secret_access_key|BEGIN [A-Z ]*PRIVATE KEY'
if git grep -InE "$secret_pattern" -- . ':!scripts/validate.sh'; then
  fail "motif de secret détecté (voir ci-dessus)"
else
  echo "OK : aucun secret détecté par motif (analyse limitée, ne remplace pas un vrai scanner)."
fi

echo
if [[ "$failures" -gt 0 ]]; then
  printf 'RÉSULTAT : %d contrôle(s) en échec\n' "$failures" >&2
  exit 1
fi
echo "RÉSULTAT : tous les contrôles sont passés"
