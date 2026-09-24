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
    return " or ".join(f'.metadata.component == "{t}"' for t in types)


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
    return {"deploy-full-stack.yaml": {"workflows": workflows}}


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
            "network/main (layer networking) depends on rds/main, which deploys later (layer data)",
        )

    def test_undeclared_state_read_of_later_layer_fails(self):
        stacks = {"s1": stack(
            rds__main=instance("rds"),
            network__main=instance("dns", {"a": ["!terraform.state rds/main .instance_address"]}),
        )}
        self.assert_errors(stacks, workflow_files(*LAYERS), "depends on rds/main, which deploys later")

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
        self.assert_errors({}, files, "layer b: vpc is also in layer a")

    def test_unsupported_query_fails(self):
        files = workflow_files(*LAYERS)
        steps = files["deploy-full-stack.yaml"]["workflows"]["deploy"]["steps"]
        steps[0]["command"] = "terraform plan --query '.vars.tags.team == \"x\"'"
        errors = check_deploy_layers.check({}, files)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("layer networking: query is not a disjunction", errors[0])

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

    def test_missing_deploy_workflow_fails(self):
        self.assert_errors({}, {}, "no `deploy` workflow")


if __name__ == "__main__":
    unittest.main()
