"""The state backends: every deployed instance of the "backend" component and the bucket it owns.

Reads the dict of `atmos describe stacks --process-functions=false --format json`.
A backend instance (backend/main in fnx-ue1-root, its EU twin in fnx-ew1-root)
creates the S3 bucket vars.bucket_name in vars.region and its access_roles; every
s3-backend instance names one of those buckets in backend.bucket. Checks resolve
a bucket's owner with owned()/owner_of(), never by picking one of several.
"""
import re
from dataclasses import dataclass, field
from typing import Optional

BACKEND_COMPONENT = "backend"
# A template over an unset setting renders "<no value>" for both sides, which would compare equal.
AWS_REGION = re.compile(r"^[a-z]{2}(-[a-z]+)+-\d$")


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def instances(stack: dict) -> dict:
    return (stack.get("components") or {}).get("terraform") or {}


@dataclass(frozen=True)
class Backend:
    stack: str
    instance: str
    bucket: Optional[str]
    region: Optional[str]
    access_roles: dict = field(default_factory=dict, compare=False)

    @property
    def where(self) -> str:
        return f"{self.stack}: {self.instance}"


def backends(stacks: dict) -> list[Backend]:
    """Every deployed backend instance, in stack and instance order."""
    found = []
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(instances(stack).items()):
            if is_deployable(instance) and instance.get("component") == BACKEND_COMPONENT:
                variables = instance.get("vars") or {}
                found.append(Backend(stack_name, name, variables.get("bucket_name") or None,
                                     variables.get("region") or None, variables.get("access_roles") or {}))
    return found


def owners(stacks: dict) -> dict:
    """bucket name -> every backend that creates it (more than one is a duplicate bucket)."""
    by_bucket: dict = {}
    for backend in backends(stacks):
        if backend.bucket is not None:
            by_bucket.setdefault(backend.bucket, []).append(backend)
    return by_bucket


def owned(stacks: dict) -> tuple[dict, list[str]]:
    """(bucket -> its one owning Backend, errors). A bucket created twice has no owner;
    errors also name a backend without bucket_name, an invalid region or no access_roles."""
    errors = []
    found = backends(stacks)
    by_bucket = owners(stacks)
    if not by_bucket:
        errors.append(f"no deployed '{BACKEND_COMPONENT}' instance owns a state bucket (vars.bucket_name)")
    errors += [f"{b.where}: the deployed '{BACKEND_COMPONENT}' instance has no vars.bucket_name"
               for b in found if b.bucket is None]
    result = {}
    for bucket, creators in sorted(by_bucket.items()):
        if len(creators) > 1:
            errors.append(f"state bucket {bucket!r} is created by more than one backend instance: "
                          f"{[b.where for b in creators]}")
            continue
        owner = result[bucket] = creators[0]
        if not AWS_REGION.match(str(owner.region)):
            errors.append(f"{owner.where}: the state bucket's region {owner.region!r} is not an AWS region "
                          "(settings.tfstate.region unset?)")
        if not owner.access_roles:
            errors.append(f"{owner.where}: the deployed '{BACKEND_COMPONENT}' instance has no access_roles")
    return result, errors


def bucket_of(instance: dict) -> Optional[str]:
    """The bucket an instance's state lives in (backend.bucket)."""
    return (instance.get("backend") or {}).get("bucket") or None


def owner_of(owned_map: dict, instance: dict) -> Optional[Backend]:
    """The one backend owning the instance's bucket (owned()[0]), or None."""
    return owned_map.get(bucket_of(instance))


def assumed_role_name(instance: dict) -> Optional[str]:
    """The role name in backend.assume_role.role_arn (path stripped)."""
    arn = ((instance.get("backend") or {}).get("assume_role") or {}).get("role_arn") or ""
    return arn.rsplit(":role/", 1)[1].rsplit("/", 1)[-1] if ":role/" in arn else None


def assumed_role_key(instance: dict, backend: Backend) -> Optional[str]:
    """The key of backend's access_roles whose role_name is the role the instance assumes, or None."""
    name = assumed_role_name(instance)
    keys = [key for key, role in sorted(backend.access_roles.items()) if name and role.get("role_name") == name]
    return keys[0] if keys else None
