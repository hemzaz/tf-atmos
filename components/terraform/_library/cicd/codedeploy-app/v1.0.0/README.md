# CodeDeploy Application Module

Production-ready AWS CodeDeploy application with deployment groups for EC2, ECS, and Lambda, supporting both in-place and blue/green deployments.

## Features

- Multiple compute platforms (Server/EC2, ECS, Lambda)
- In-place and blue/green deployments
- Custom deployment configurations with traffic shifting
- Auto Scaling Group integration
- Alarm-based automatic rollback
- CloudWatch monitoring and SNS notifications
- Load balancer integration (ALB, NLB, CLB)
- Custom deployment strategies (canary, linear)

## Example - EC2 Blue/Green Deployment

```hcl
module "codedeploy_app" {
  source = "../../_library/cicd/codedeploy-app/v1.0.0"

  name             = "my-app"
  compute_platform = "Server"

  # Target EC2 instances by tags
  ec2_tag_filters = [
    {
      key   = "Environment"
      type  = "KEY_AND_VALUE"
      value = "production"
    },
    {
      key   = "Application"
      type  = "KEY_AND_VALUE"
      value = "my-app"
    }
  ]

  # Auto Scaling Groups
  autoscaling_groups = ["my-app-asg"]

  # Blue/Green deployment
  deployment_type   = "BLUE_GREEN"
  deployment_option = "WITH_TRAFFIC_CONTROL"

  blue_green_deployment_config = {
    terminate_blue_instances_on_deployment_success = {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
    deployment_ready_option = {
      action_on_timeout    = "CONTINUE_DEPLOYMENT"
      wait_time_in_minutes = 0
    }
    green_fleet_provisioning_option = {
      action = "COPY_AUTO_SCALING_GROUP"
    }
  }

  # Load balancer
  load_balancer_info = {
    target_group_arns = ["arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/my-app/xxx"]
  }

  # Auto rollback on failure
  enable_auto_rollback  = true
  auto_rollback_events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]

  # CloudWatch alarms for monitoring
  alarm_configuration = {
    enabled     = true
    alarm_names = ["my-app-high-error-rate", "my-app-high-latency"]
  }

  # SNS notifications
  trigger_configurations = [
    {
      trigger_name       = "deployment-notifications"
      trigger_events     = ["DeploymentStart", "DeploymentSuccess", "DeploymentFailure"]
      trigger_target_arn = "arn:aws:sns:us-east-1:123456789012:deployments"
    }
  ]

  tags = {
    Environment = "production"
    Application = "my-app"
  }
}
```
