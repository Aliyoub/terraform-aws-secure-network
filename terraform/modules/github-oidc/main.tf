# Fournisseur d'identité OIDC de GitHub Actions. Un seul par compte AWS : si ce module
# est utilisé pour plusieurs dépôts, ce fournisseur doit être créé une fois et partagé
# (voir var.create_oidc_provider).
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [var.thumbprint]

  tags = {
    Name = "${var.name_prefix}-github-oidc"
  }
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn

  # Repo cible dans le claim "sub", avec ses identifiants immuables si fournis
  # (repo:owner@owner_id/repo@repo_id, format utilisé par GitHub pour les dépôts créés
  # après le 15/07/2026 ou ayant activé les "immutable subject claims" - voir
  # var.github_owner_id). Sans ces identifiants, le format simple owner/repo est utilisé.
  repo_claim = (
    var.github_owner_id != null
    ? "${var.github_organization}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}"
    : "${var.github_organization}/${var.github_repository}"
  )

  # Motifs du claim "sub" du jeton GitHub Actions autorisés à endosser le rôle :
  # un par branche autorisée, plus un pour les pull requests si activées.
  sub_patterns = concat(
    [for b in var.allowed_branches : "repo:${local.repo_claim}:ref:refs/heads/${b}"],
    var.allow_pull_requests ? ["repo:${local.repo_claim}:pull_request"] : []
  )
}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # Empêche un autre fournisseur OIDC de se faire passer pour GitHub Actions.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restreint aux branches et/ou pull requests du dépôt désigné : un fork ou un autre
    # dépôt ne reçoit pas de jeton dont le "sub" correspond à ces motifs.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.sub_patterns
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.name_prefix}-github-actions-${var.role_purpose}"
  description          = var.role_description
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration

  tags = {
    Name = "${var.name_prefix}-github-actions-${var.role_purpose}"
  }
}

data "aws_iam_policy_document" "permissions" {
  count = length(var.read_only_actions) > 0 ? 1 : 0

  statement {
    sid       = "ReadOnly"
    effect    = "Allow"
    actions   = var.read_only_actions
    resources = ["*"] # La plupart des actions Describe* EC2/IAM n'acceptent pas de portée par ressource.
  }
}

resource "aws_iam_policy" "permissions" {
  count = length(var.read_only_actions) > 0 ? 1 : 0

  name        = "${var.name_prefix}-github-actions-${var.role_purpose}-policy"
  description = "Lecture seule pour terraform plan - aucune action de creation, modification ou suppression."
  policy      = data.aws_iam_policy_document.permissions[0].json
}

resource "aws_iam_role_policy_attachment" "permissions" {
  count = length(var.read_only_actions) > 0 ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.permissions[0].arn
}
