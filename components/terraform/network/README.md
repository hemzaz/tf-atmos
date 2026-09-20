# network

VPC peering connection and cross-VPC routes.

Creates one `aws_vpc_peering_connection` between two VPCs in the same account
and region, plus the `aws_route` entries on each side that make it carry
traffic. A peering connection on its own routes nothing — both directions need
a route pointing the peer's CIDR at the connection — so this component always
creates the routes alongside it.

## Deployed as

| Instance | Stack | What it connects |
|---|---|---|
| `network/vpc-peering` | `fnx-prod-production` | `vpc/main` (10.20.0.0/16) ↔ `vpc/services` (10.21.0.0/16) |

| Input | Notes |
|---|---|
| `region` | AWS region; validated against the AWS region name format |
| `name_prefix` | `tenant-account-environment`; the connection is named `${name_prefix}-peering` |
| `enabled` | Set `false` to make the component create nothing |
| `tags` | **Required, no default.** Must contain a non-empty `Environment` |
| `create_vpc_peering` | Create the connection and its routes (default `true`) |
| `requester_vpc_id` / `accepter_vpc_id` | VPC ids; the requester initiates, the accepter accepts |
| `auto_accept` | Accept automatically. Same account and region only (default `true`) |
| `requester_routes` / `accepter_routes` | `[{ destination_cidr_block, route_table_ids }]` — see below |

Outputs: `vpc_peering_connection_id`, `vpc_peering_accept_status`, `route_ids`,
plus `name_prefix` and `enabled`.

## Dependencies / gotchas

- **`network/*` instances are not all this component.** `network/main` and
  `network/services` are `dns` instances (Atmos keys on `metadata.component`,
  not the instance prefix); only `network/vpc-peering` resolves here. The
  prefix is a stack-naming convention, so read `metadata.component` before
  assuming which module an instance runs.
- **Route table ids are passed in, not discovered.** Each route entry carries
  `route_table_ids` explicitly, sourced from the peer VPC's
  `private_route_table_ids` output via `!terraform.state`. A data-source lookup
  would be less typing in the stack, but it would hide the `vpc -> network`
  edge from `check-dependencies.py`, which reads `!terraform.state` references
  to order deployments. The explicit wiring is what makes the edge visible.
- **Private route tables only** in the prod instance. The peer CIDR needs to be
  reachable from the application tier; adding it to the public tables would
  route peer traffic through internet-facing subnets for no gain.
- `auto_accept` only works when both VPCs are in the same account and region.
  Cross-account peering must be accepted by the peer through
  `aws_vpc_peering_connection_accepter`, which this component does not create.
- **Not exercised by the sandbox.** `atmos workflow sandbox` applies `kms`,
  `vpc`, `dns`, `secretsmanager` and `ecs` only; there is no peering instance
  in `fnx-local-sandbox`. This component is covered by `terraform validate`,
  tflint and the scanners, but nothing has executed it against an API.
- `tags` is deliberately **required**. A `default = {}` makes every resource
  look untagged to tflint and checkov, which run per-component without stack
  vars.
- Resources are tagged via the provider's `default_tags`, not per resource.
  The connection additionally sets a `Name` tag.

## Usage

```
atmos terraform plan network/vpc-peering -s fnx-prod-production
```
