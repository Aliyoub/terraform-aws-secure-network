#!/usr/bin/env bash
# Garde-fou de coût : signale toute ressource ou module potentiellement payant
# INSTANCIÉ SANS ÊTRE PROTÉGÉ par un interrupteur `count = var.enable_x ? 1 : 0`
# dont la variable `enable_x` vaut `false` par défaut, dans les fichiers racine
# de chaque environnement (terraform/environments/*/main.tf).
#
# Ne scanne PAS terraform/modules/ : un module peut légitimement contenir des
# ressources payantes (ex. modules/rds) sans risque tant qu'il n'est pas instancié.
# Le risque réel se situe au point où un environnement l'instancie - c'est ce point
# qui est vérifié ici, pas le contenu des modules eux-mêmes.
#
# Analyse statique par expressions régulières, pas un vrai parseur HCL : limité,
# ne remplace pas une relecture humaine avant tout apply. Aucun appel AWS, rien créé.
#
# Usage : scripts/check-aws-cost-risk.sh
# ALLOW_PAID_RESOURCES=1 pour outrepasser un échec (à documenter dans le commit).
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - "$@" <<'PYEOF'
import glob
import re
import sys

PAID_RESOURCE_TYPES = {
    "aws_nat_gateway", "aws_eip", "aws_eip_association", "aws_lb", "aws_alb",
    "aws_elb", "aws_instance", "aws_launch_template", "aws_autoscaling_group",
    "aws_db_instance", "aws_rds_cluster", "aws_vpc_endpoint", "aws_flow_log",
    "aws_cloudwatch_log_group", "aws_ec2_transit_gateway", "aws_vpn_connection",
    "aws_ebs_volume", "aws_kms_key",
}
# Modules connus du projet dont l'instanciation crée des ressources payantes.
PAID_MODULE_SOURCE_HINTS = (
    "modules/nat-gateway", "modules/vpc-endpoints", "modules/ec2-instance",
    "modules/alb", "modules/rds",
)

BLOCK_START_RE = re.compile(
    r'^(?P<indent>[ \t]*)(?:resource\s+"(?P<rtype>[a-z0-9_]+)"\s+"[^"]+"|module\s+"(?P<mname>[a-z0-9_]+)")\s*\{'
)
COUNT_RE = re.compile(r'count\s*=\s*var\.([a-zA-Z0-9_]+)\s*\?')
SOURCE_RE = re.compile(r'source\s*=\s*"([^"]+)"')
VAR_BLOCK_RE = re.compile(r'variable\s+"([a-zA-Z0-9_]+)"\s*\{')
DEFAULT_FALSE_RE = re.compile(r'default\s*=\s*false\b')


def extract_block(lines, start_idx, indent):
    """Retourne les lignes du bloc HCL démarrant à start_idx, jusqu'à l'accolade
    fermante de même indentation (heuristique suffisante pour ce projet)."""
    block = [lines[start_idx]]
    for line in lines[start_idx + 1:]:
        block.append(line)
        if line.rstrip() == f"{indent}}}":
            break
    return block


def bool_vars_defaulting_false(variables_tf_path):
    try:
        text = open(variables_tf_path, encoding="utf-8").read()
    except FileNotFoundError:
        return set()
    names = set()
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = VAR_BLOCK_RE.match(lines[i].strip())
        if m:
            block = extract_block(lines, i, "")
            block_text = "\n".join(block)
            if DEFAULT_FALSE_RE.search(block_text):
                names.add(m.group(1))
            i += len(block)
        else:
            i += 1
    return names


def check_file(main_tf_path, variables_tf_path):
    safe_vars = bool_vars_defaulting_false(variables_tf_path)
    text = open(main_tf_path, encoding="utf-8").read()
    lines = text.splitlines()
    findings = []
    i = 0
    while i < len(lines):
        m = BLOCK_START_RE.match(lines[i])
        if not m:
            i += 1
            continue
        indent = m.group("indent")
        rtype = m.group("rtype")
        mname = m.group("mname")
        block = extract_block(lines, i, indent)
        block_text = "\n".join(block)

        is_paid_resource = rtype in PAID_RESOURCE_TYPES
        is_paid_module = mname is not None and any(
            h in (SOURCE_RE.search(block_text).group(1) if SOURCE_RE.search(block_text) else "")
            for h in PAID_MODULE_SOURCE_HINTS
        )

        if is_paid_resource or is_paid_module:
            label = f'resource "{rtype}"' if is_paid_resource else f'module "{mname}"'
            cm = COUNT_RE.search(block_text)
            gated = bool(cm and cm.group(1) in safe_vars)
            findings.append((i + 1, label, gated, cm.group(1) if cm else None))
        i += len(block)
    return findings


def main():
    ungated = []
    gated = []
    for main_tf in sorted(glob.glob("terraform/environments/*/main.tf")):
        env_dir = main_tf.rsplit("/", 1)[0]
        variables_tf = f"{env_dir}/variables.tf"
        for lineno, label, is_gated, varname in check_file(main_tf, variables_tf):
            entry = f"{main_tf}:{lineno}: {label}" + (f" (gardé par var.{varname}, false par défaut)" if is_gated else "")
            (gated if is_gated else ungated).append(entry)

    print(f"Recherche de ressources/modules potentiellement payants dans terraform/environments/*/main.tf")
    if gated:
        print("\nProtégés par un interrupteur désactivé par défaut (informatif, pas un échec) :")
        for e in gated:
            print(f"  {e}")

    if ungated:
        print("\nNON protégés par un interrupteur désactivé par défaut :")
        for e in ungated:
            print(f"  {e}")
        print()
        import os
        if os.environ.get("ALLOW_PAID_RESOURCES") == "1":
            print("ATTENTION : ALLOW_PAID_RESOURCES=1, poursuite malgré tout.")
            print("Vérifier docs/COSTS.md et prévoir le nettoyage avant tout apply.")
            sys.exit(0)
        print("ÉCHEC : ces ressources peuvent engendrer des coûts par défaut, sans garde-fou.")
        print("Ajouter un interrupteur (count = var.enable_x ? 1 : 0, avec enable_x par défaut à false),")
        print("relire docs/COSTS.md, ou relancer avec ALLOW_PAID_RESOURCES=1 si c'est voulu.")
        sys.exit(1)

    print("\nOK : aucune ressource/module potentiellement payant sans garde-fou.")
    sys.exit(0)


main()
PYEOF
