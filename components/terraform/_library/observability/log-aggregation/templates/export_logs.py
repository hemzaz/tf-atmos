"""Export the previous 24h of every log group under LOG_GROUP_PREFIX to S3.

CloudWatch Logs allows one running export task per account, so groups are
exported sequentially and each task is awaited before the next is created.
"""
import os
import time

import boto3

logs = boto3.client("logs")


def _wait(task_id):
    while True:
        task = logs.describe_export_tasks(taskId=task_id)["exportTasks"][0]
        if task["status"]["code"] not in ("PENDING", "RUNNING"):
            return task["status"]["code"]
        time.sleep(5)


def handler(event, context):
    bucket = os.environ["S3_BUCKET"]
    prefix = os.environ["LOG_GROUP_PREFIX"]
    end = int(time.time() * 1000)
    start = end - 24 * 60 * 60 * 1000
    results = {}

    paginator = logs.get_paginator("describe_log_groups")
    for page in paginator.paginate(logGroupNamePrefix=prefix):
        for group in page["logGroups"]:
            name = group["logGroupName"]
            task = logs.create_export_task(
                logGroupName=name,
                fromTime=start,
                to=end,
                destination=bucket,
                destinationPrefix="exports" + name,
            )
            results[name] = _wait(task["taskId"])

    return results
