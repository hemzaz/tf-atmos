#!/usr/bin/env python3
"""Check each SQS queue that feeds a Lambda against that function's timeout.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
A lambda instance's vars.event_source_mappings.<key>.event_source_arn that reads a
queue (`!terraform.state <sqs instance> [<stack>] .queue_arn`, the instance a
metadata.component: sqs one) pairs the queue with the function. For each pair:
  - ERROR when the queue's vars.visibility_timeout_seconds is below the function's
    vars.timeout: AWS rejects the event source mapping;
  - WARN when it is below 6 x timeout + 5 (the AWS guidance: a retry after a timeout
    must not become visible while the function still runs); WARN lines never fail.
A mapping whose ARN is not a queue read (a Kinesis stream, a literal ARN) is ignored, as
is a queue no lambda reads. An omitted visibility_timeout_seconds or timeout is the
component's default (DEFAULT_VISIBILITY, DEFAULT_TIMEOUT: variables.tf), as it is for
Terraform. A value that is not a number, or a read of an instance the stack lacks, is
WARNed and skipped (check-dependencies reports a missing instance). A lambda with
metadata.enabled: false is checked too: it is the one switched on later. Abstract
instances are skipped. Exits 1 on any ERROR.
"""
import json
import os
import sys
from typing import Optional

# The sibling module, also when this file is loaded by path (tests).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixtures  # noqa: E402

CHECK = "check-sqs-visibility"
READ = "!terraform.state"
QUEUE_OUTPUT = ".queue_arn"
# components/terraform/{sqs,lambda}/variables.tf
DEFAULT_VISIBILITY = 30
DEFAULT_TIMEOUT = 3


def instances(stack: dict, component: str) -> dict:
    return {
        name: instance
        for name, instance in ((stack.get("components") or {}).get("terraform") or {}).items()
        if (instance or {}).get("metadata", {}).get("type") != "abstract"
        and (instance or {}).get("metadata", {}).get("component") == component
    }


def queue_read(arn) -> Optional[tuple[str, str]]:
    """(instance, stack or "") a `!terraform.state <instance> [<stack>] .queue_arn` read names."""
    if not isinstance(arn, str):
        return None
    parts = arn.split()
    if len(parts) not in (3, 4) or parts[0] != READ or parts[-1] != QUEUE_OUTPUT:
        return None
    return parts[1], parts[2] if len(parts) == 4 else ""


def seconds(value, default: int) -> Optional[int]:
    """The value as seconds (default when omitted); None when it is not a number."""
    if value is None:
        return default
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return value


def check(stacks: dict) -> tuple[list[str], list[str]]:
    errors, warnings = [], []
    for stack_name, stack in sorted(stacks.items()):
        queues = instances(stack, "sqs")
        for name, function in sorted(instances(stack, "lambda").items()):
            fvars = function.get("vars") or {}
            for key, mapping in sorted((fvars.get("event_source_mappings") or {}).items()):
                read = queue_read((mapping or {}).get("event_source_arn"))
                if read is None:
                    continue
                queue_name, queue_stack = read
                where = f"{stack_name}: {name} event_source_mappings.{key} (queue {queue_name})"
                queue = queues.get(queue_name) if queue_stack in ("", stack_name) else None
                if queue is None:
                    warnings.append(f"{where} reads a queue this stack's sqs instances lack, skipped")
                    continue
                visibility = seconds((queue.get("vars") or {}).get("visibility_timeout_seconds"), DEFAULT_VISIBILITY)
                timeout = seconds(fvars.get("timeout"), DEFAULT_TIMEOUT)
                if visibility is None or timeout is None:
                    warnings.append(f"{where} has a visibility_timeout_seconds or timeout that is not a number, skipped")
                elif visibility < timeout:
                    errors.append(
                        f"{where}: visibility_timeout_seconds {visibility} is below the function timeout {timeout}"
                        " (AWS rejects the mapping)"
                    )
                elif visibility < 6 * timeout + 5:
                    warnings.append(
                        f"{where}: visibility_timeout_seconds {visibility} is below 6 x timeout + 5 = {6 * timeout + 5}"
                        f" (function timeout {timeout})"
                    )
    return errors, warnings


def main() -> int:
    errors, warnings = check(json.load(sys.stdin))
    for warning in warnings:
        print(f"WARN {warning}")
    errors = fixtures.fatal(errors, CHECK)
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} SQS visibility timeout problem(s)")
        return 1
    print("every SQS queue feeding a Lambda has a visibility timeout of at least the function timeout")
    return 0


if __name__ == "__main__":
    sys.exit(main())
