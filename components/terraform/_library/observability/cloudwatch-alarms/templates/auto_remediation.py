"""CloudWatch alarm Lambda action: optional Slack notice plus simple remediation.

Supported ENABLED_ACTIONS entries:
  restart_instance - reboot the EC2 instance in the alarm's InstanceId dimension
  scale_up         - add one instance to the ASG in the AutoScalingGroupName dimension
"""
import json
import os
import urllib.request

import boto3


def _dimensions(event):
    dims = {}
    for metric in event["alarmData"]["configuration"].get("metrics", []):
        stat = metric.get("metricStat", {}).get("metric", {})
        dims.update(stat.get("dimensions", {}))
    return dims


def _notify(text):
    url = os.environ.get("SLACK_WEBHOOK_URL", "")
    if not url:
        return
    body = json.dumps({"text": text}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=10)


def handler(event, context):
    alarm = event["alarmData"]["alarmName"]
    state = event["alarmData"]["state"]["value"]
    actions = json.loads(os.environ.get("ENABLED_ACTIONS", "[]"))
    dims = _dimensions(event)
    taken = []

    if state == "ALARM":
        if "restart_instance" in actions and "InstanceId" in dims:
            boto3.client("ec2").reboot_instances(InstanceIds=[dims["InstanceId"]])
            taken.append(f"rebooted {dims['InstanceId']}")
        if "scale_up" in actions and "AutoScalingGroupName" in dims:
            asg = boto3.client("autoscaling")
            name = dims["AutoScalingGroupName"]
            group = asg.describe_auto_scaling_groups(AutoScalingGroupNames=[name])["AutoScalingGroups"][0]
            desired = min(group["DesiredCapacity"] + 1, group["MaxSize"])
            asg.set_desired_capacity(AutoScalingGroupName=name, DesiredCapacity=desired)
            taken.append(f"scaled {name} to {desired}")

    _notify(f"{alarm} is {state}. Actions: {', '.join(taken) or 'none'}")
    return {"alarm": alarm, "state": state, "actions": taken}
