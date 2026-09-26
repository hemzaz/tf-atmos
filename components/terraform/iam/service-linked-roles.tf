# AWS Auto Scaling's service-linked role. kms/main's allow_autoscaling_ebs
# grant (catalog/kms/defaults.yaml) names
# arn:<partition>:iam::<account>:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling
# as a principal so that EBS volumes on a CMK-encrypted node-group launch
# template can be created. AWS KMS validates every IAM principal named in a
# key policy at CreateKey/PutKeyPolicy time and rejects the policy with
# MalformedPolicyDocumentException ("invalid principals") if the role does
# not exist yet - the role is created automatically the first time an
# account uses Auto Scaling, but nothing guarantees that has happened before
# kms/main's first apply. iam runs in the layer before kms
# (workflows/deploy-full-stack.yaml), so this is the natural place to
# provision it. Mirrors cloudposse-terraform-components/aws-iam-service-linked-roles'
# create-if-absent pattern: aws_iam_service_linked_role errors
# ("has been taken in this account") if the role already exists, so this
# looks the role up first and only creates it when the lookup finds nothing.
data "aws_iam_roles" "existing_autoscaling_slr" {
  name_regex  = "AWSServiceRoleForAutoScaling"
  path_prefix = "/aws-service-role/autoscaling.amazonaws.com/"
}

resource "aws_iam_service_linked_role" "autoscaling" {
  count            = var.manage_autoscaling_service_linked_role && length(data.aws_iam_roles.existing_autoscaling_slr.names) == 0 ? 1 : 0
  aws_service_name = "autoscaling.amazonaws.com"
  description      = "Grants Auto Scaling permission to launch, terminate and describe EC2 instances on this account's behalf. Provisioned here so kms/main's allow_autoscaling_ebs key-policy grant (catalog/kms/defaults.yaml) names a principal that exists."
}
