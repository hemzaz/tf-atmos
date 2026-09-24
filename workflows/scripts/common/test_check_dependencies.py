"""Tests for check-dependencies.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import tempfile
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

    def test_terraform_output_bare_name_is_not_a_stack(self):
        reader = instance({"b": "!terraform.output vpc/main vpc_id"}, [{"component": "vpc/main"}])
        self.assert_errors(stacks_with(reader))

    def test_expression_start_characters_are_not_stacks(self):
        for expression in (".id", "[.a]", "{a: .b}", "| .id", "'.id'", '".id"'):
            with self.subTest(expression=expression):
                reader = instance(
                    {"x": f"!terraform.state vpc/main {expression} // null"}, [{"component": "vpc/main"}]
                )
                self.assertEqual(
                    list(check_dependencies.references(reader["vars"])), [("vpc/main", None)]
                )
                self.assert_errors(stacks_with(reader))

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

    def test_missing_component_directory_fails(self):
        # Nothing else catches this: atmos validate stacks and validate-all both
        # pass when a deployable instance names a component that was never written.
        with tempfile.TemporaryDirectory() as components:
            pathlib.Path(components, "vpc").mkdir()
            stacks = {"s1": {"components": {"terraform": {
                "vpc/main": instance(component="vpc"),
                "cache/main": instance(component="elasticache"),
            }}}}
            errors = check_dependencies.check(stacks, components)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("cache/main", errors[0])
        self.assertIn("elasticache does not exist", errors[0])

    def test_component_directory_check_skipped_when_dir_not_given(self):
        stacks = {"s1": {"components": {"terraform": {"nope/main": instance(component="nope")}}}}
        self.assertEqual(check_dependencies.check(stacks), [])

    def test_abstract_and_disabled_instances_need_no_directory(self):
        with tempfile.TemporaryDirectory() as components:
            stacks = {"s1": {"components": {"terraform": {
                "base": instance(component="ghost", type="abstract"),
                "off": instance(component="ghost", enabled=False),
            }}}}
            self.assertEqual(check_dependencies.check(stacks, components), [])



if __name__ == "__main__":
    unittest.main()
