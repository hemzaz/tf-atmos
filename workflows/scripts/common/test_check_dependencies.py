"""Tests for check-dependencies.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_dependencies", pathlib.Path(__file__).with_name("check-dependencies.py")
)
check_dependencies = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_dependencies)


def instance(variables=None, deps=None, **metadata):
    return {"metadata": metadata, "vars": variables or {}, "dependencies": {"components": deps or []}}


def stacks_with(reader, **extra_stacks):
    stacks = {
        "s1": {
            "components": {
                "terraform": {
                    "vpc/main": instance(),
                    "vpc": instance(type="abstract"),
                    "off": instance(enabled=False),
                    "reader": reader,
                }
            }
        }
    }
    for name, components in extra_stacks.items():
        stacks[name] = {"components": {"terraform": components}}
    return stacks


class CheckDependenciesTest(unittest.TestCase):
    def assert_errors(self, stacks, *fragments):
        errors = check_dependencies.check(stacks)
        self.assertEqual(len(errors), len(fragments), errors)
        for error, fragment in zip(errors, fragments):
            self.assertIn(fragment, error)

    def test_declared_dependency_passes(self):
        reader = instance({"x": "!terraform.state vpc/main .id"}, [{"component": "vpc/main"}])
        self.assert_errors(stacks_with(reader))

    def test_undeclared_dependency_fails(self):
        self.assert_errors(stacks_with(instance({"x": "!terraform.state vpc/main .id"})), "does not list it")

    def test_nested_terraform_output_is_found(self):
        reader = instance({"a": [{"b": "!terraform.output vpc/main .id"}]})
        self.assert_errors(stacks_with(reader), "does not list it")

    def test_missing_target_fails(self):
        reader = instance({"x": "!terraform.state nope .id"}, [{"component": "nope"}])
        self.assert_errors(stacks_with(reader), "does not exist")

    def test_abstract_and_disabled_targets_fail(self):
        reader = instance(
            {"a": "!terraform.state vpc .id", "b": "!terraform.state off .id"},
            [{"component": "vpc"}, {"component": "off"}],
        )
        self.assert_errors(stacks_with(reader), "reads off, which is abstract", "reads vpc, which is abstract")

    def test_disabled_reader_is_skipped(self):
        self.assert_errors(stacks_with(instance({"x": "!terraform.state nope .id"}, enabled=False)))

    def test_jq_expression_with_spaces(self):
        reader = instance({"x": "!terraform.state vpc/main [.a // {} | .[]]"}, [{"component": "vpc/main"}])
        self.assert_errors(stacks_with(reader))

    def test_cross_stack_reference_needs_stack_in_dependency(self):
        reader = instance({"x": "!terraform.state vpc/main s2 .id"}, [{"component": "vpc/main"}])
        self.assert_errors(stacks_with(reader, s2={"vpc/main": instance()}), "in s2 but does not list it")

    def test_cross_stack_reference_with_stack_passes(self):
        reader = instance({"x": "!terraform.state vpc/main s2 .id"}, [{"component": "vpc/main", "stack": "s2"}])
        self.assert_errors(stacks_with(reader, s2={"vpc/main": instance()}))


if __name__ == "__main__":
    unittest.main()
