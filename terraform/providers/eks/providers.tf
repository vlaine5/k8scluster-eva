# =============================================================================
#  Provider AWS. Les identifiants viennent des mécanismes standards d'AWS :
#  AWS_PROFILE, AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN,
#  ou ~/.aws/config. Aucun identifiant n'est écrit dans ce dépôt.
#
#  aws_target = "localstack" envoie exactement les mêmes ressources vers
#  LocalStack (émulateur local). Les identifiants factices "test" et les
#  contrôles désactivés ci-dessous ne s'appliquent QU'À LocalStack, jamais à
#  AWS : avec aws_target = "aws", toutes ces valeurs restent celles d'AWS.
# =============================================================================

locals {
  localstack = var.aws_target == "localstack"
}

provider "aws" {
  region = var.aws_region

  access_key                  = local.localstack ? "test" : null
  secret_key                  = local.localstack ? "test" : null
  skip_credentials_validation = local.localstack
  skip_metadata_api_check     = local.localstack
  skip_requesting_account_id  = local.localstack

  dynamic "endpoints" {
    for_each = local.localstack ? [var.localstack_endpoint] : []
    content {
      ec2 = endpoints.value
      eks = endpoints.value
      iam = endpoints.value
      sts = endpoints.value
    }
  }

  # Étiquettes posées sur toutes les ressources : on retrouve facilement ce
  # que le lab a créé (console AWS, facturation, nettoyage).
  default_tags {
    tags = {
      Project   = "k8s-lab"
      Cluster   = var.cluster_name
      ManagedBy = "terraform"
    }
  }
}
