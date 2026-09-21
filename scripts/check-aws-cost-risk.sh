#!/usr/bin/env bash
# Garde-fou de coût : signale les ressources Terraform potentiellement payantes.
#
# Analyse statique du code, sans appel AWS et sans rien créer.
# Échoue (code 1) si une telle ressource est déclarée, sauf si ALLOW_PAID_RESOURCES=1.
#
# Usage : scripts/check-aws-cost-risk.sh [répertoire]   (défaut : terraform/)
set -euo pipefail

cd "$(dirname "$0")/.."
target="${1:-terraform}"

# Types de ressources qui peuvent être facturés (à l'heure, au volume ou à l'IP publique).
paid_types=(
  aws_nat_gateway
  aws_eip
  aws_eip_association
  aws_lb
  aws_alb
  aws_elb
  aws_instance
  aws_launch_template
  aws_autoscaling_group
  aws_db_instance
  aws_rds_cluster
  aws_vpc_endpoint
  aws_flow_log
  aws_cloudwatch_log_group
  aws_ec2_transit_gateway
  aws_vpn_connection
  aws_ebs_volume
  aws_kms_key
)

pattern="^[[:space:]]*resource[[:space:]]+\"($(IFS='|'; echo "${paid_types[*]}"))\""

if [[ ! -d "$target" ]]; then
  echo "Répertoire introuvable : $target" >&2
  exit 2
fi

echo "Recherche de ressources potentiellement payantes dans : $target"

if matches=$(grep -rEn --include='*.tf' "$pattern" "$target"); then
  echo
  echo "Ressources potentiellement payantes déclarées :"
  echo "$matches" | sed 's/^/  /'
  echo
  if [[ "${ALLOW_PAID_RESOURCES:-0}" == "1" ]]; then
    echo "ATTENTION : ALLOW_PAID_RESOURCES=1, poursuite malgré tout."
    echo "Vérifier docs/COSTS.md et prévoir le nettoyage avant tout apply."
    exit 0
  fi
  echo "ÉCHEC : ces ressources peuvent engendrer des coûts."
  echo "Relire docs/COSTS.md, puis relancer avec ALLOW_PAID_RESOURCES=1 si c'est voulu."
  exit 1
fi

echo "OK : aucune ressource potentiellement payante déclarée."
