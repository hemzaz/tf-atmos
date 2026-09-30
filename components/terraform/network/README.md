# network

One VPC peering connection between two VPCs in the same account and region, plus the routes on
both sides that make it carry traffic.

## Wiring

- Instance: `network/vpc-peering` in the three AWS stacks, peering `vpc/main` with `vpc/services`.
- Reads: `vpc/main` and `vpc/services` `.vpc_id` and `.private_route_table_ids`.
- Used by: nothing reads its state; `eks/data` lists it in `dependencies.components`, because the
  bastion (`vpc/main`) reaches that cluster's private endpoint over it (docs/OPERATIONS.md,
  "In-cluster components").

## Notes

- `network/main` and `network/services` are `dns` instances, not this component.
- Route table IDs are passed in through `!terraform.state`, not looked up by a data source, so
  `check-dependencies.py` sees the `vpc -> network` edge. Only private route tables are routed.
- `auto_accept` works only within one account and region; cross-account peering needs an
  `aws_vpc_peering_connection_accepter`, which this component does not create.
- `tags` is required (no default) and must contain a non-empty `Environment`.
