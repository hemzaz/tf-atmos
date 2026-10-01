"""Tests for check-secret-attributes.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import unittest

_HERE = pathlib.Path(__file__)
_spec = importlib.util.spec_from_file_location(
    "check_secret_attributes", _HERE.with_name("check-secret-attributes.py")
)
check_secret_attributes = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_secret_attributes)

VARIABLES_TF = _HERE.parents[3] / "components" / "terraform" / "secretsmanager" / "variables.tf"


def stacks_with(secrets, component="secretsmanager", **metadata):
    return {
        "fnx-prod-production": {
            "components": {
                "terraform": {
                    "secretsmanager/app": {"component": component, "metadata": metadata, "vars": {"secrets": secrets}}
                }
            }
        }
    }


class CheckSecretAttributesTest(unittest.TestCase):
    allowed = check_secret_attributes.allowed_attributes(VARIABLES_TF.read_text())

    def assert_errors(self, stacks, *fragments):
        errors = check_secret_attributes.check(stacks, self.allowed)
        self.assertEqual(len(errors), len(fragments), errors)
        for error, fragment in zip(errors, fragments):
            self.assertIn(fragment, error)

    def test_parses_the_component_attribute_set(self):
        self.assertIn("password_length", self.allowed)
        self.assertIn("random_password_override_special", self.allowed)
        self.assertIn("secret_data", self.allowed)
        self.assertNotIn("type", self.allowed)

    def test_known_attributes_pass(self):
        self.assert_errors(stacks_with({"db": {"name": "db", "generate_random_password": True, "password_length": 48}}))

    def test_misspelled_attribute_fails(self):
        self.assert_errors(
            stacks_with({"db": {"name": "db", "pasword_length": 48}}),
            "secrets.db has unknown attribute(s) pasword_length",
        )

    def test_abstract_instance_is_checked(self):
        # Its vars are inherited by the real instances.
        self.assert_errors(stacks_with({"db": {"nmae": "db"}}, type="abstract"), "unknown attribute(s) nmae")

    def test_non_mapping_entry_fails(self):
        self.assert_errors(stacks_with({"db": "db"}), "is not a mapping")

    def test_other_components_are_ignored(self):
        self.assert_errors(stacks_with({"db": {"anything": 1}}, component="rds"))

    def test_no_secrets_passes(self):
        self.assert_errors(stacks_with(None))

    def test_missing_variable_raises(self):
        with self.assertRaises(ValueError):
            check_secret_attributes.allowed_attributes('variable "other" {\n  type = string\n}\n')


if __name__ == "__main__":
    unittest.main()
