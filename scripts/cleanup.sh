#!/usr/bin/env bash
# Cleanup sécurisé de l'environnement dev (terraform/environments/dev) UNIQUEMENT.
#
# Ce script formalise, sous forme rejouable, la procédure suivie manuellement tout au
# long de ce projet (inventaire -> confirmation -> destruction -> vérification
# indépendante). Il ne touche jamais terraform/environments/bootstrap (fournisseur OIDC
# + rôle IAM de la CI) : ce périmètre est volontairement exclu, en dur, ci-dessous.
#
# Ce que fait ce script :
#   1. Affiche les ressources actuellement suivies par le state de dev.
#   2. Affiche un plan de destruction réel (terraform plan -destroy).
#   3. Demande une confirmation explicite (il faut taper exactement "detruire").
#   4. Lance terraform destroy uniquement après cette confirmation.
#   5. Vérifie ensuite, par des appels AWS CLI indépendants filtrés sur le tag
#      Project=terraform-aws-secure-network, qu'aucune ressource du projet ne subsiste.
#
# Ce que ce script NE fait PAS :
#   - Il ne supprime jamais de ressource en dehors de terraform/environments/dev.
#   - Il ne devine jamais une confirmation : une réponse vide, "y", "yes" ou "oui" est
#     refusée. Seul le mot exact "detruire" est accepté.
#   - Il n'affiche aucun credential.
#
# Usage :
#   scripts/cleanup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_DIR="${REPO_ROOT}/terraform/environments/dev"
PROJECT_TAG="terraform-aws-secure-network"
REGION="${AWS_REGION:-eu-west-3}"

if [[ ! -d "${ENV_DIR}" ]]; then
  echo "ERREUR : répertoire introuvable : ${ENV_DIR}" >&2
  exit 1
fi

echo "=== Cleanup de l'environnement dev (${ENV_DIR}) ==="
echo "Région AWS ciblée pour la vérification : ${REGION}"
echo

echo "--- Identité AWS active (aucun credential affiché) ---"
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output table

cd "${ENV_DIR}"

echo
echo "--- Ressources actuellement suivies par le state ---"
if ! terraform state list 2>/dev/null; then
  echo "(aucune, ou state non initialisé)"
fi

RESOURCE_COUNT="$(terraform state list 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${RESOURCE_COUNT}" -eq 0 ]]; then
  echo
  echo "Aucune ressource dans le state : rien à détruire. Fin."
  exit 0
fi

echo
echo "--- Plan de destruction (terraform plan -destroy) ---"
terraform plan -destroy -input=false -out=/tmp/cleanup-dev.tfplan
terraform show /tmp/cleanup-dev.tfplan

echo
echo "=== ${RESOURCE_COUNT} ressource(s) actuellement dans le state de dev seraient détruites ci-dessus ==="
echo
echo "Ce cleanup NE touche PAS terraform/environments/bootstrap (fournisseur OIDC, rôle IAM de la CI)."
echo "Pour confirmer, tape exactement : detruire"
read -r -p "> " CONFIRMATION

if [[ "${CONFIRMATION}" != "detruire" ]]; then
  echo "Confirmation non reçue (\"${CONFIRMATION}\" != \"detruire\"). Abandon, rien n'a été détruit."
  rm -f /tmp/cleanup-dev.tfplan
  exit 1
fi

echo
echo "--- Destruction en cours ---"
terraform apply -input=false /tmp/cleanup-dev.tfplan
rm -f /tmp/cleanup-dev.tfplan

echo
echo "--- Vérification indépendante côté AWS (filtrée sur tag Project=${PROJECT_TAG}) ---"

remaining=0
check() {
  local label="$1"
  local output="$2"
  if [[ -n "${output// /}" ]]; then
    echo "RESTANT [${label}] : ${output}"
    remaining=1
  else
    echo "OK [${label}] : aucune ressource restante"
  fi
}

check "VPC" "$(aws ec2 describe-vpcs --region "${REGION}" --filters "Name=tag:Project,Values=${PROJECT_TAG}" --query 'Vpcs[].VpcId' --output text)"
check "NAT Gateways (actifs)" "$(aws ec2 describe-nat-gateways --region "${REGION}" --filter "Name=tag:Project,Values=${PROJECT_TAG}" --query "NatGateways[?State!='deleted'].NatGatewayId" --output text)"
check "Elastic IP" "$(aws ec2 describe-addresses --region "${REGION}" --filters "Name=tag:Project,Values=${PROJECT_TAG}" --query 'Addresses[].PublicIp' --output text)"
check "Instances EC2 (actives)" "$(aws ec2 describe-instances --region "${REGION}" --filters "Name=tag:Project,Values=${PROJECT_TAG}" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text)"
check "Load Balancers" "$(aws elbv2 describe-load-balancers --region "${REGION}" --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT_TAG}')].LoadBalancerArn" --output text)"
check "Target Groups" "$(aws elbv2 describe-target-groups --region "${REGION}" --query "TargetGroups[?contains(TargetGroupName, '${PROJECT_TAG}')].TargetGroupArn" --output text)"
check "RDS" "$(aws rds describe-db-instances --region "${REGION}" --query "DBInstances[?contains(DBInstanceIdentifier, '${PROJECT_TAG}')].DBInstanceIdentifier" --output text 2>/dev/null || true)"
check "VPC Endpoints (actifs)" "$(aws ec2 describe-vpc-endpoints --region "${REGION}" --filters "Name=tag:Project,Values=${PROJECT_TAG}" --query "VpcEndpoints[?State!='deleted'].VpcEndpointId" --output text)"
check "Security Groups" "$(aws ec2 describe-security-groups --region "${REGION}" --filters "Name=tag:Project,Values=${PROJECT_TAG}" --query 'SecurityGroups[].GroupId' --output text)"
check "CloudWatch Log Groups" "$(aws logs describe-log-groups --region "${REGION}" --log-group-name-prefix "/${PROJECT_TAG}" --query 'logGroups[].logGroupName' --output text)"
check "Rôles IAM du projet (ec2-ssm, flow-logs)" "$(aws iam list-roles --query "Roles[?contains(RoleName, '${PROJECT_TAG}-dev-ec2-ssm') || contains(RoleName, '${PROJECT_TAG}-dev-flow-logs')].RoleName" --output text)"

echo
if [[ "${remaining}" -eq 0 ]]; then
  echo "RÉSULTAT : CLEAN — aucune ressource du projet détectée après destruction."
else
  echo "RÉSULTAT : ATTENTION — au moins une ressource listée ci-dessus subsiste. Ne pas supposer qu'elle est gratuite : vérifier manuellement avant de la considérer comme résiduelle sans risque."
fi
