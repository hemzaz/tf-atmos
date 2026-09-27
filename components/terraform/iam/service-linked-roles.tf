# AWS Auto Scaling's service-linked role. kms/main's allow_autoscaling_ebs
# grant (catalog/kms/defaults.yaml) names
# arn:<partition>:iam::<account>:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling
# directly as a key-policy principal - AWS's documented same-account pattern
# (Example 1,
# https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html)
# - so that EBS volumes on a CMK-encrypted node-group launch template can be
# created. AWS KMS validates every IAM principal named in a key policy at
# CreateKey/PutKeyPolicy time and rejects the policy with
# MalformedPolicyDocumentException ("invalid principals") if the role does
# not exist yet - the role is created automatically the first time an
# account uses Auto Scaling, but nothing guarantees that has happened before
# kms/main's first apply. iam runs in the layer before kms
# (workflows/deploy-full-stack.yaml), so this is the natural place to
# provision it.
#
# This resource is gated only by a static bool, never by a data-source
# lookup of the role it creates: an earlier design looked the role up first
# (aws_iam_roles) and created it only when the lookup found nothing, but that
# makes the lookup depend on this resource's own prior apply - every plan
# after the first would find the just-created role and plan to destroy it.
# There is no live AWS state in this repo (no migration concern from that
# design), so instead enable_autoscaling_service_linked_role is set true on
# exactly one iam instance per account (iam/dev in dev, iam/main in staging
# and prod) and left false everywhere else, including iam/ci - see the
# variable description.
resource "aws_iam_service_linked_role" "autoscaling" {
  count            = var.enable_autoscaling_service_linked_role ? 1 : 0
  aws_service_name = "autoscaling.amazonaws.com"
  description      = "Grants Auto Scaling permission to launch, terminate and describe EC2 instances on this account's behalf. Provisioned here so kms/main's allow_autoscaling_ebs key-policy grant (catalog/kms/defaults.yaml) names a principal that exists before kms/main applies."
}
