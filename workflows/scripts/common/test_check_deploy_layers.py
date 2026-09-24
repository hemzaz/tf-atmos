"""Tests for check-deploy-layers.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_deploy_layers", pathlib.Path(__file__).with_name("check-deploy-layers.py")
)
check_deploy_layers = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_deploy_layers)


def query(*types):
    """`a` -> .metadata.component == "a"; a term that already starts with `.` is kept as is."""
    return " or ".join(t if t.startswith(".") else f'.metadata.component == "{t}"' for t in types)


def workflow_files(*layers, per_layer=True):
    """deploy-full-stack.yaml as `atmos describe workflows --output all --format json` returns it."""
    steps, workflows = [], {}
    for layer, types in layers:
        q = query(*types)
        steps += [
            {"name": f"plan-{layer}", "type": "atmos", "command": f"terraform plan --query '{q}'"},
            {"name": f"confirm_{layer}", "type": "confirm", "command": ""},
            {"name": f"deploy-{layer}", "type": "atmos", "command": f"terraform deploy --from-plan --query '{q}'"},
        ]
        if per_layer:
            workflows[f"deploy-{layer}"] = {"steps": [
                {"name": "plan", "type": "atmos", "command": f"terraform plan --query '{q}'"},
                {"name": "deploy", "type": "atmos", "command": f"terraform deploy --from-plan --query '{q}'"},
            ]}
    workflows["deploy"] = {"steps": steps}
    return {"deploy-full-stack.yaml": {"workflows": workflows}, **SUBSET_WORKFLOWS}


def subset_workflow(*steps):
    """A deploy-app style workflow: ("plan", types) / ("deploy", types) steps in order."""
    kinds = {"plan": "terraform plan --log-order grouped --query", "deploy": "terraform deploy --from-plan --query"}
    return {"steps": [
        {"name": f"{kind}-{i}", "type": "atmos", "command": f"{kinds[kind]} '{query(*types)}'"}
        for i, (kind, types) in enumerate(steps)
    ]}


# Minimal valid deploy-app and bootstrap `full` workflows that select nothing the tests use.
SUBSET_WORKFLOWS = {
    "deploy-application.yaml": {"workflows": {"deploy-app": subset_workflow(("plan", ["x"]), ("deploy", ["x"]))}},
    "bootstrap.yaml": {"workflows": {"full": subset_workflow(("plan", ["x"]), ("deploy", ["x"]))}},
}


def instance(component, variables=None, deps=None, **metadata):
    return {
        "metadata": {"component": component, **metadata},
        "vars": variables or {},
        "dependencies": {"components": deps or []},
    }


def stack(**instances):
    return {"components": {"terraform": {name.replace("__", "/"): i for name, i in instances.items()}}}


LAYERS = (("networking", ["vpc", "dns"]), ("data", ["rds"]), ("services", ["apigateway"]))


class CheckDeployLayersTest(unittest.TestCase):
    def assert_errors(self, stacks, files, *fragments):
        errors = check_deploy_layers.check(stacks, files)
        self.assertEqual(len(errors), len(fragments), errors)
        for error, fragment in zip(errors, fragments):
            self.assertIn(fragment, error)

    def test_ordered_stack_passes(self):
        stacks = {"s1": stack(
            vpc__main=instance("vpc"),
            rds__main=instance("rds", {"x": "!terraform.state vpc/main .id"}, [{"component": "vpc/main"}]),
            api__main=instance("apigateway", deps=[{"component": "rds/main"}]),
        )}
        self.assert_errors(stacks, workflow_files(*LAYERS))

    def test_instance_in_no_layer_fails(self):
        stacks = {"s1": stack(cognito__main=instance("cognito"))}
        self.assert_errors(stacks, workflow_files(*LAYERS), "cognito/main (metadata.component 'cognito') is in no layer")

    def test_disabled_and_abstract_instances_need_no_layer(self):
        stacks = {"s1": stack(off=instance("cognito", enabled=False), base=instance("cognito", type="abstract"))}
        self.assert_errors(stacks, workflow_files(*LAYERS))

    def test_dependency_in_later_layer_fails(self):
        # The prod bug: dns (networking) declares rds/main (data).
        stacks = {"s1": stack(
            rds__main=instance("rds"),
            network__main=instance("dns", deps=[{"component": "rds/main"}]),
        )}
        self.assert_errors(
            stacks, workflow_files(*LAYERS),
            "network/main (plan step plan-networking) depends on rds/main, which deploys later (step deploy-data)",
        )

    def test_undeclared_state_read_of_later_layer_fails(self):
        stacks = {"s1": stack(
            rds__main=instance("rds"),
            network__main=instance("dns", {"a": ["!terraform.state rds/main .instance_address"]}),
        )}
        self.assert_errors(stacks, workflow_files(*LAYERS), "reads rds/main, which deploys later (plan step plan-data)")

    def test_same_layer_dependency_passes(self):
        stacks = {"s1": stack(vpc__main=instance("vpc"), dns__main=instance("dns", deps=[{"component": "vpc/main"}]))}
        self.assert_errors(stacks, workflow_files(*LAYERS))

    def test_cross_stack_dependency_is_not_ordered_here(self):
        stacks = {
            "s1": stack(vpc__main=instance("vpc", deps=[{"component": "rds/main", "stack": "s2"}])),
            "s2": stack(rds__main=instance("rds")),
        }
        self.assert_errors(stacks, workflow_files(*LAYERS))

    def test_missing_dependency_is_left_to_check_dependencies(self):
        stacks = {"s1": stack(vpc__main=instance("vpc", deps=[{"component": "nope/main"}]))}
        self.assert_errors(stacks, workflow_files(*LAYERS))

    def test_type_in_two_layers_fails(self):
        files = workflow_files(("a", ["vpc"]), ("b", ["vpc", "rds"]))
        stacks = {"s1": stack(vpc__main=instance("vpc"))}
        self.assert_errors(stacks, files, "vpc/main is planned by more than one step: plan-a, plan-b")

    def test_unsupported_query_fails(self):
        files = workflow_files(*LAYERS)
        steps = files["deploy-full-stack.yaml"]["workflows"]["deploy"]["steps"]
        steps[0]["command"] = "terraform plan --query '.vars.tags.team == \"x\"'"
        errors = check_deploy_layers.check({}, files)
        self.assertTrue(errors, errors)
        self.assertIn("step plan-networking: query is not an or/and", errors[0])

    # A layer plans every instance before it applies any: a read inside one layer
    # finds no state on the first deploy.
    def test_same_layer_state_read_fails(self):
        stacks = {"s1": stack(
            vpc__main=instance("vpc"),
            dns__main=instance("dns", {"id": "!terraform.state vpc/main .vpc_id"}, [{"component": "vpc/main"}]),
        )}
        self.assert_errors(
            stacks, workflow_files(*LAYERS),
            "dns/main (plan step plan-networking) reads vpc/main, which is planned in the same phase, before it is applied",
        )

    def test_same_layer_output_read_fails(self):
        stacks = {"s1": stack(
            vpc__main=instance("vpc"),
            dns__main=instance("dns", {"id": "!terraform.output vpc/main vpc_id"}),
        )}
        self.assert_errors(stacks, workflow_files(*LAYERS), "dns/main (plan step plan-networking) reads vpc/main")

    def test_same_layer_read_with_explicit_own_stack_fails(self):
        stacks = {"s1": stack(
            vpc__main=instance("vpc"),
            dns__main=instance("dns", {"id": "!terraform.state vpc/main s1 .vpc_id"}),
        )}
        self.assert_errors(stacks, workflow_files(*LAYERS), "dns/main (plan step plan-networking) reads vpc/main")

    def test_same_type_read_split_by_instance_name_passes(self):
        # ec2/app-server reads ec2/bastion: the bastion is selected by name into an earlier layer.
        layers = (
            ("access", ['.atmos_component == "ec2/bastion"']),
            ("compute", ['.metadata.component == "ec2" and .atmos_component != "ec2/bastion"']),
        )
        stacks = {"s1": stack(
            ec2__bastion=instance("ec2"),
            ec2__app_server=instance("ec2", {"sg": "!terraform.state ec2/bastion .security_group_id"}),
        )}
        self.assert_errors(stacks, workflow_files(*layers))

    def test_same_type_read_in_one_layer_fails(self):
        stacks = {"s1": stack(
            ec2__bastion=instance("ec2"),
            ec2__app_server=instance("ec2", {"sg": "!terraform.state ec2/bastion .security_group_id"}),
        )}
        self.assert_errors(
            stacks, workflow_files(("compute", ["ec2"])),
            "ec2/app_server (plan step plan-compute) reads ec2/bastion, which is planned in the same phase",
        )

    def test_instance_selected_by_no_layer_after_name_split_fails(self):
        layers = (("access", ['.atmos_component == "ec2/bastion"']),)
        stacks = {"s1": stack(ec2__bastion=instance("ec2"), ec2__web=instance("ec2"))}
        self.assert_errors(stacks, workflow_files(*layers), "ec2/web (metadata.component 'ec2') is in no layer")

    def test_layer_for_a_type_no_stack_uses_is_harmless(self):
        stacks = {"s1": stack(vpc__main=instance("vpc"))}
        self.assert_errors(stacks, workflow_files(("networking", ["vpc"]), ("security-monitoring", ["security-monitoring"])))

    def test_dependency_with_context_keys_is_cross_stack(self):
        stacks = {"s1": stack(
            vpc__main=instance("vpc", deps=[{"component": "rds/main", "tenant": "fnx", "stage": "prod"}]),
            rds__main=instance("rds"),
        )}
        self.assert_errors(stacks, workflow_files(*LAYERS))

    def test_dependency_naming_own_stack_is_ordered(self):
        stacks = {"s1": stack(
            vpc__main=instance("vpc", deps=[{"component": "rds/main", "stack": "s1"}]),
            rds__main=instance("rds"),
        )}
        self.assert_errors(stacks, workflow_files(*LAYERS), "vpc/main (plan step plan-networking) depends on rds/main")


    def test_deploy_step_query_drift_fails(self):
        files = workflow_files(*LAYERS)
        steps = files["deploy-full-stack.yaml"]["workflows"]["deploy"]["steps"]
        steps[2]["command"] = f"terraform deploy --from-plan --query '{query('vpc')}'"
        self.assert_errors({}, files, "step deploy-networking of `deploy` does not use the query")

    def test_per_layer_workflow_drift_fails(self):
        files = workflow_files(*LAYERS)
        files["deploy-full-stack.yaml"]["workflows"]["deploy-data"]["steps"][0]["command"] = (
            f"terraform plan --query '{query('rds', 'elasticache')}'"
        )
        self.assert_errors({}, files, "workflow deploy-data (plan) does not use the query")

    def test_missing_per_layer_workflow_fails(self):
        files = workflow_files(*LAYERS)
        del files["deploy-full-stack.yaml"]["workflows"]["deploy-services"]
        self.assert_errors(
            {}, files,
            "workflow deploy-services (plan) does not use the query",
            "workflow deploy-services (deploy) does not use the query",
        )

    def test_multiline_folded_query_is_normalised(self):
        files = workflow_files(*LAYERS)
        steps = files["deploy-full-stack.yaml"]["workflows"]["deploy"]["steps"]
        steps[0]["command"] = "terraform plan --query '.metadata.component == \"vpc\"\n or .metadata.component == \"dns\"'"
        self.assert_errors({}, files)

    def test_missing_workflows_fail(self):
        self.assert_errors(
            {}, {},
            "deploy-full-stack.yaml `deploy`: no such workflow",
            "deploy-application.yaml `deploy-app`: no such workflow",
            "bootstrap.yaml `full`: no such workflow",
        )


class SubsetWorkflowTest(unittest.TestCase):
    """deploy-app / bootstrap `full`: a subset of instances in plan/apply phases."""

    STACKS = {"s1": stack(
        cognito__main=instance("cognito"),
        lambda__fn=instance("lambda"),
        api__main=instance(
            "apigateway",
            {"a": "!terraform.state cognito/main .user_pool_arn", "b": "!terraform.state lambda/fn .arn"},
            [{"component": "cognito/main"}, {"component": "lambda/fn"}],
        ),
        vpc__main=instance("vpc"),
    )}

    def errors(self, *steps):
        files = workflow_files(("networking", ["vpc"]), ("services", ["cognito", "lambda", "apigateway"]))
        files["deploy-application.yaml"] = {"workflows": {"deploy-app": subset_workflow(*steps)}}
        return [e for e in check_deploy_layers.check(self.STACKS, files) if e.startswith("deploy-application.yaml")]

    def test_reader_planned_after_its_targets_are_applied_passes(self):
        self.assertEqual(self.errors(
            ("plan", ["cognito", "lambda"]), ("deploy", ["cognito"]), ("deploy", ["lambda"]),
            ("plan", ["apigateway"]), ("deploy", ["apigateway"]),
        ), [])

    def test_reader_planned_with_its_targets_fails(self):
        # The deploy-app bug: cognito, lambda and apigateway in one plan.
        errors = self.errors(
            ("plan", ["cognito", "lambda", "apigateway"]),
            ("deploy", ["cognito"]), ("deploy", ["lambda"]), ("deploy", ["apigateway"]),
        )
        self.assertEqual(len(errors), 2, errors)
        self.assertIn("api/main (plan step plan-0) reads cognito/main, which is planned in the same phase", errors[0])
        self.assertIn("reads lambda/fn, which is planned in the same phase", errors[1])

    def test_unselected_dependency_is_assumed_deployed(self):
        self.assertEqual(self.errors(("plan", ["apigateway"]), ("deploy", ["apigateway"])), [])

    def test_planned_but_never_applied_fails(self):
        errors = self.errors(("plan", ["cognito", "lambda"]), ("deploy", ["cognito"]))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("lambda/fn is planned by plan-0 but applied by no step", errors[0])

    def test_applied_without_a_plan_fails(self):
        errors = self.errors(("plan", ["cognito"]), ("deploy", ["cognito", "lambda"]))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("lambda/fn is applied by step deploy-1, whose phase did not plan it", errors[0])

    def test_applied_twice_fails(self):
        errors = self.errors(("plan", ["cognito"]), ("deploy", ["cognito"]), ("deploy", ["cognito"]))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("cognito/main is planned by plan-0 but applied by deploy-1, deploy-2", errors[0])

    def test_declared_only_dependency_applied_by_a_later_step_fails(self):
        stacks = {"s1": stack(
            vpc__main=instance("vpc"),
            ecs__main=instance("ecs", deps=[{"component": "vpc/main"}]),
        )}
        files = workflow_files(("networking", ["vpc", "ecs"]))
        files["deploy-application.yaml"] = {"workflows": {"deploy-app": subset_workflow(
            ("plan", ["vpc", "ecs"]), ("deploy", ["ecs"]), ("deploy", ["vpc"]),
        )}}
        errors = [e for e in check_deploy_layers.check(stacks, files) if e.startswith("deploy-application.yaml")]
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("ecs/main (plan step plan-0) depends on vpc/main, which deploys later (step deploy-2)", errors[0])

    def test_single_instance_steps_are_understood(self):
        files = workflow_files(("networking", ["vpc"]), ("services", ["cognito", "lambda", "apigateway"]))
        files["deploy-application.yaml"] = {"workflows": {"deploy-app": {"steps": [
            {"name": "plan", "command": "terraform plan cognito/main"},
            {"name": "deploy", "command": "terraform deploy cognito/main --from-plan"},
            {"name": "plan-api", "command": "terraform plan api/main"},
            {"name": "deploy-api", "command": "terraform deploy api/main --from-plan"},
        ]}}}
        errors = [e for e in check_deploy_layers.check(self.STACKS, files) if e.startswith("deploy-application.yaml")]
        self.assertEqual(errors, [])

    def test_and_before_the_last_or_is_rejected(self):
        # yq v4.52: `a and b or c` groups as `a and (b or c)`, not `(a and b) or c`.
        errors = self.errors(
            ("plan", ['.metadata.component == "ec2" and .atmos_component != "ec2/x"', "cognito"]),
            ("deploy", ["cognito"]),
        )
        self.assertIn("step plan-0: query is not an or/and", errors[0], errors)

    def test_and_in_the_last_disjunct_groups_to_the_right(self):
        query = check_deploy_layers.parse_query(
            '.metadata.component == "cognito" or .metadata.component == "lambda" and .atmos_component != "lambda/fn"'
        )
        self.assertIsNotNone(query)
        instances = self.STACKS["s1"]["components"]["terraform"]
        selected = sorted(n for n, i in instances.items() if check_deploy_layers.selects(query, n, i))
        self.assertEqual(selected, ["cognito/main"])

    def test_unparsed_terraform_step_fails(self):
        files = workflow_files(("networking", ["vpc"]))
        files["deploy-application.yaml"] = {"workflows": {"deploy-app": {"steps": [
            {"name": "plan", "command": "terraform plan --query '.metadata.component == \"x\"'"},
            {"name": "deploy", "command": "terraform deploy --from-plan --query '.metadata.component == \"x\"'"},
            {"name": "apply", "command": "terraform apply cognito/main -auto-approve"},
            {"name": "sneaky", "command": "terraform deploy --query '.metadata.component == \"cognito\"'"},
            {"name": "output", "command": "terraform output vpc/main vpc_id"},
        ]}}}
        errors = [e for e in check_deploy_layers.check(self.STACKS, files) if e.startswith("deploy-application.yaml")]
        self.assertEqual(len(errors), 2, errors)
        self.assertIn("step apply: `terraform apply cognito/main -auto-approve` is not a plan/deploy form", errors[0])
        self.assertIn("step sneaky:", errors[1])

    def test_deploy_before_any_plan_fails(self):
        errors = self.errors(("deploy", ["cognito"]))
        self.assertTrue(any("applies planfiles before any plan step" in e for e in errors), errors)

    def test_bootstrap_full_is_checked(self):
        files = workflow_files(("networking", ["vpc"]), ("services", ["cognito", "lambda", "apigateway"]))
        files["bootstrap.yaml"] = {"workflows": {"full": subset_workflow(
            ("plan", ["lambda", "apigateway"]), ("deploy", ["lambda", "apigateway"]),
        )}}
        errors = [e for e in check_deploy_layers.check(self.STACKS, files) if e.startswith("bootstrap.yaml")]
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("reads lambda/fn, which is planned in the same phase", errors[0])


if __name__ == "__main__":
    unittest.main()
