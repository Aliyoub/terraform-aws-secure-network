# terraform-aws-secure-network

Réseau AWS sécurisé (VPC, subnets publics/privés, routage, Security Groups) construit avec Terraform, dans une démarche maîtrisée des coûts : aucune ressource facturable n'est créée par défaut, et chaque démonstration payante est suivie d'un nettoyage vérifié.

> **Statut :** projet en cours. Phases 1 (squelette) et 2 (code du VPC et des subnets) écrites. Rien n'est encore déployé sur AWS.

## Objectifs

- Concevoir un VPC multi-AZ avec une segmentation stricte entre subnets publics et privés.
- Appliquer le principe du moindre privilège aux Security Groups (aucun SSH public).
- Authentifier la CI auprès d'AWS avec GitHub OIDC, sans clé d'accès statique.
- Rendre les coûts explicites : NAT Gateway, load balancers, Flow Logs et endpoints sont optionnels et désactivés par défaut.

## Structure du dépôt

```
terraform/
  modules/              modules réutilisables (ajoutés phase par phase)
  environments/dev/     module racine de l'environnement dev
docs/                   architecture, sécurité, coûts, décisions, dépannage
screenshots/            preuves capturées au fil du projet
scripts/                scripts de validation et de nettoyage
.github/workflows/      CI (validate, plan). Aucun apply automatique
```

## Utilisation

```bash
cd terraform/environments/dev
terraform init
terraform fmt -check
terraform validate
```

`terraform apply` n'est jamais exécuté automatiquement.

## Auteur

Binaté Aliyou, DevOps / Cloud Engineer.

## Licence

MIT
