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

    def test_quoted_expression_with_spaces_is_not_a_stack(self):
        # Atmos reads a quoted token as one expression: '.id | [.]' wraps the
        # output in a list. Splitting it on spaces read "'.id" as a stack name.
        reader = instance(
            {"x": "!terraform.state vpc/main '.id | [.]'", "y": '!terraform.state vpc/main ".id | [.]"'},
            [{"component": "vpc/main"}],
        )
        self.assert_errors(stacks_with(reader))

    def test_cross_stack_reference_with_quoted_expression(self):
        reader = instance({"x": "!terraform.state vpc/main s2 '.id | [.]'"}, [{"component": "vpc/main", "stack": "s2"}])
        self.assert_errors(stacks_with(reader, s2={"vpc/main": instance()}))

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


class OutputsAndVariablesTest(unittest.TestCase):
    """Reads of undeclared outputs, and vars the module does not declare (components_dir given)."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.components = tmp.name
        vpc = pathlib.Path(tmp.name, "vpc")
        vpc.mkdir()
        (vpc / "outputs.tf").write_text('output "vpc_id" {\n  value = 1\n}\n\noutput "subnet_ids" {\n  value = {}\n}\n')
        (vpc / "variables.tf").write_text('variable "cidr" {\n  type = string\n}\n')
        pathlib.Path(tmp.name, "app").mkdir()
        pathlib.Path(tmp.name, "app", "variables.tf").write_text('variable "x" {}\nvariable "y" {}\n')

    def reader(self, value, *deps):
        return instance({"x": value}, [{"component": "vpc/main", **dep} for dep in deps or ({},)], component="app")

    def errors(self, reader, **extra_stacks):
        stacks = {"s1": {"components": {"terraform": {
            "vpc/main": instance(component="vpc"),
            "vpc/off": instance(component="vpc", enabled=False),
            "reader": reader,
        }}}}
        for name, components in extra_stacks.items():
            stacks[name] = {"components": {"terraform": components}}
        return check_dependencies.check(stacks, self.components)

    def test_declared_output_passes(self):
        self.assertEqual(self.errors(self.reader("!terraform.state vpc/main .vpc_id")), [])

    def test_missing_output_fails(self):
        errors = self.errors(self.reader("!terraform.state vpc/main .vpc_idz"))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("reads vpc/main output vpc_idz (.vpc_idz), which", errors[0])
        self.assertIn("vpc does not declare", errors[0])

    def test_missing_output_behind_default_still_fails(self):
        self.assertEqual(len(self.errors(self.reader("!terraform.state vpc/main .nope // null"))), 1)

    def test_nested_path_checks_first_segment(self):
        self.assertEqual(self.errors(self.reader("!terraform.state vpc/main .subnet_ids.private[0]")), [])
        errors = self.errors(self.reader("!terraform.state vpc/main .subnets.private"))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("output subnets ", errors[0])

    def test_cross_stack_read_checks_target_stack_module(self):
        reader = self.reader("!terraform.state vpc/main s2 .vpc_idz", {"stack": "s2"})
        errors = self.errors(reader, s2={"vpc/main": instance(component="vpc")})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("reads vpc/main in s2 output vpc_idz", errors[0])

    def test_terraform_output_bare_name(self):
        self.assertEqual(self.errors(self.reader("!terraform.output vpc/main vpc_id")), [])
        self.assertEqual(len(self.errors(self.reader("!terraform.output vpc/main vpc_idz"))), 1)

    def test_disabled_target_reports_only_disabled(self):
        reader = instance({"x": "!terraform.state vpc/off .nope"}, [{"component": "vpc/off"}], component="app")
        errors = self.errors(reader)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("abstract or disabled", errors[0])

    def test_output_name(self):
        cases = {
            ".vpc_id": "vpc_id",
            ".queue_arns.tasks": "queue_arns",
            ".foo[0]": "foo",
            '.["vpc_id"]': "vpc_id",
            "[.a // {} | .[]]": "a",
            "'.id | [.]'": "id",
            "vpc_id": "vpc_id",
            ".": None,
            ".{{ .settings.x }}": None,
        }
        for expression, want in cases.items():
            with self.subTest(expression=expression):
                self.assertEqual(check_dependencies.output_name(expression), want)

    def test_undeclared_vars(self):
        stacks = {"s1": {"components": {"terraform": {
            "ok": instance({"x": 1, "y": 2}, component="app"),
            "bad": instance({"x": 1, "z": 3, "w": 4}, component="app"),
            "off": instance({"z": 3}, component="app", enabled=False),
            "ghost": instance({"z": 3}, component="nope"),
        }}}}
        problems = check_dependencies.undeclared_vars(stacks, self.components)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("s1: bad sets w, z, which", problems[0])


if __name__ == "__main__":
    unittest.main()
