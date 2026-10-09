"""The state backends: every deployed instance of the "backend" component and the bucket it owns.

Reads the dict of `atmos describe stacks --process-functions=false --format json`.
A backend instance (backend/main in fnx-ue1-root, its EU twin in fnx-ew1-root)
creates the S3 bucket vars.bucket_name in vars.region and its access_roles; every
s3-backend instance names one of those buckets in backend.bucket.
"""
from dataclasses import dataclass, field
from typing import Optional

BACKEND_COMPONENT = "backend"


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

    def role_names(self) -> set:
        """The IAM role names of its access roles (what a backend's role_arn ends in)."""
        return {role.get("role_name") for role in self.access_roles.values()} - {None}


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
    """bucket name -> the backends that create it (more than one is a duplicate bucket)."""
    by_bucket: dict = {}
    for backend in backends(stacks):
        if backend.bucket is not None:
            by_bucket.setdefault(backend.bucket, []).append(backend)
    return by_bucket


def bucket_of(instance: dict) -> Optional[str]:
    """The bucket an instance's state lives in (backend.bucket)."""
    return (instance.get("backend") or {}).get("bucket") or None


def assumed_role_name(instance: dict) -> Optional[str]:
    """The role name in backend.assume_role.role_arn (path stripped)."""
    arn = ((instance.get("backend") or {}).get("assume_role") or {}).get("role_arn") or ""
    return arn.rsplit(":role/", 1)[1].rsplit("/", 1)[-1] if ":role/" in arn else None
