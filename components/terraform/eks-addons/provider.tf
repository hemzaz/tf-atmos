provider "aws" {
  region = var.region

  assume_role {
    role_arn = var.assume_role_arn
  }

  default_tags {
    tags = var.default_tags
  }
}

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

# We intentionally use explicit providers to avoid circular dependencies
# between eks and eks-addons modules.
# This allows the eks-addons module to consume outputs from the eks module 
# without creating circular dependencies.
#
# IMPORTANT: The eks-addons module must be applied AFTER the eks module.
# Deployment order:
# 1. First apply the eks module
# 2. Then apply the eks-addons module
# Violating this order will result in runtime errors due to missing cluster credentials.

provider "kubectl" {
  host = length(var.clusters) > 0 ? lookup(
    var.clusters[keys(var.clusters)[0]],
    "kubernetes_host",
    var.host
  ) : var.host
  
  cluster_ca_certificate = length(var.clusters) > 0 ? base64decode(
    lookup(
      var.clusters[keys(var.clusters)[0]],
      "cluster_ca_certificate",
      var.cluster_ca_certificate
    )
  ) : base64decode(var.cluster_ca_certificate)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args = [
      "eks", 
      "get-token", 
      "--cluster-name",
      length(var.clusters) > 0 ? lookup(
        var.clusters[keys(var.clusters)[0]],
        "cluster_name",
        var.cluster_name
      ) : var.cluster_name,
      "--region", 
      var.region
    ]
    command = "aws"
  }
}