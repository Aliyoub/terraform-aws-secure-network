#!/usr/bin/env bash
# Test réseau (Phase 9) : vérifie, contre le compte AWS réel, que l'isolation
# public/privé annoncée dans docs/ARCHITECTURE.md est effective.
#
# Lecture seule : n'appelle que des actions ec2:Describe*, ne crée ni ne modifie
# rien. Nécessite que l'environnement dev soit déployé (terraform apply).
#
# Usage : scripts/network-isolation-check.sh [région]   (défaut : eu-west-3)
set -euo pipefail

region="${1:-eu-west-3}"
project_tag="terraform-aws-secure-network"
failures=0

step() { printf '\n== %s ==\n' "$1"; }
pass() { printf 'OK   : %s\n' "$1"; }
fail() { printf 'ÉCHEC: %s\n' "$1" >&2; failures=$((failures + 1)); }

vpc_id=$(aws ec2 describe-vpcs --region "$region" \
  --filters "Name=tag:Project,Values=${project_tag}" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)

if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
  echo "Aucun VPC taggé Project=${project_tag} trouvé en ${region}." >&2
  echo "L'environnement dev doit être déployé (terraform apply) avant ce test." >&2
  exit 2
fi
echo "VPC testé : $vpc_id (région $region)"

step "1/4 Table(s) privée(s) : aucune route vers 0.0.0.0/0"
private_rts=$(aws ec2 describe-route-tables --region "$region" \
  --filters "Name=vpc-id,Values=${vpc_id}" "Name=tag:Tier,Values=private" \
  --query 'RouteTables[].RouteTableId' --output text)
if [[ -z "$private_rts" ]]; then
  fail "aucune table de routage taguée Tier=private trouvée"
else
  for rt in $private_rts; do
    default_route=$(aws ec2 describe-route-tables --region "$region" --route-table-ids "$rt" \
      --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0']" --output text)
    if [[ -n "$default_route" ]]; then
      fail "$rt a une route 0.0.0.0/0 : sortie Internet possible depuis un subnet privé"
    else
      pass "$rt n'a aucune route par défaut vers Internet"
    fi
  done
fi

step "2/4 Table publique : route vers 0.0.0.0/0 exclusivement via un Internet Gateway"
public_rts=$(aws ec2 describe-route-tables --region "$region" \
  --filters "Name=vpc-id,Values=${vpc_id}" "Name=tag:Tier,Values=public" \
  --query 'RouteTables[].RouteTableId' --output text)
if [[ -z "$public_rts" ]]; then
  fail "aucune table de routage taguée Tier=public trouvée"
else
  for rt in $public_rts; do
    igw_route=$(aws ec2 describe-route-tables --region "$region" --route-table-ids "$rt" \
      --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId" --output text)
    if [[ "$igw_route" == igw-* ]]; then
      pass "$rt route 0.0.0.0/0 vers $igw_route (Internet Gateway, pas un NAT ni une instance)"
    else
      fail "$rt n'a pas de route 0.0.0.0/0 valide vers un Internet Gateway (trouvé : '${igw_route:-aucune}')"
    fi
  done
fi

step "3/4 Subnets privés : aucune attribution automatique d'IP publique"
private_subnets=$(aws ec2 describe-subnets --region "$region" \
  --filters "Name=vpc-id,Values=${vpc_id}" "Name=tag:Tier,Values=private" \
  --query 'Subnets[].[SubnetId,MapPublicIpOnLaunch]' --output text)
while IFS=$'\t' read -r subnet_id map_public; do
  [[ -z "$subnet_id" ]] && continue
  if [[ "$map_public" == "False" ]]; then
    pass "$subnet_id : MapPublicIpOnLaunch=False"
  else
    fail "$subnet_id attribue une IP publique automatiquement (MapPublicIpOnLaunch=True)"
  fi
done <<<"$private_subnets"

step "4/4 Security Groups : aucune règle entrante ouverte à 0.0.0.0/0, aucun port 22"
sg_ids=$(aws ec2 describe-security-groups --region "$region" \
  --filters "Name=vpc-id,Values=${vpc_id}" \
  --query 'SecurityGroups[].GroupId' --output text)
# --output text sépare les valeurs par des tabulations : tout espace blanc devient une virgule.
sg_ids_csv=$(echo "$sg_ids" | tr -s '[:space:]' ',' | sed 's/,$//')
# Projection explicite des champs affichés : ne jamais inclure GroupOwnerId (l'ID de
# compte AWS), que describe-security-group-rules renvoie par défaut avec chaque règle.
rule_fields='{SecurityGroupRuleId:SecurityGroupRuleId,GroupId:GroupId,Protocol:IpProtocol,FromPort:FromPort,ToPort:ToPort,CidrIpv4:CidrIpv4}'
open_rules=$(aws ec2 describe-security-group-rules --region "$region" \
  --filters "Name=group-id,Values=${sg_ids_csv}" \
  --query "SecurityGroupRules[?IsEgress==\`false\` && CidrIpv4=='0.0.0.0/0'].${rule_fields}" --output text)
if [[ -n "$open_rules" ]]; then
  fail "au moins une règle entrante autorise 0.0.0.0/0 (voir détail ci-dessus)"
  echo "$open_rules" >&2
else
  pass "aucune règle entrante n'autorise 0.0.0.0/0, sur aucun des $(echo "$sg_ids" | wc -w | tr -d ' ') Security Groups"
fi
ssh_rules=$(aws ec2 describe-security-group-rules --region "$region" \
  --filters "Name=group-id,Values=${sg_ids_csv}" \
  --query "SecurityGroupRules[?IsEgress==\`false\` && FromPort==\`22\`].${rule_fields}" --output text)
if [[ -n "$ssh_rules" ]]; then
  fail "au moins une règle entrante ouvre le port 22 (SSH)"
else
  pass "aucune règle entrante sur le port 22 (SSH)"
fi

echo
if [[ "$failures" -gt 0 ]]; then
  printf 'RÉSULTAT : %d vérification(s) en échec — isolation NON confirmée\n' "$failures" >&2
  exit 1
fi
echo "RÉSULTAT : isolation public/privé confirmée sur l'infrastructure réelle ($vpc_id)"
