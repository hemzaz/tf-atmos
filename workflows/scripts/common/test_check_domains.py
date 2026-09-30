"""Tests for check-domains.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_domains", pathlib.Path(__file__).with_name("check-domains.py")
)
check_domains = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_domains)

DOMAIN = "staging.fnx.example.com"


def instance(component, variables, **metadata):
    return {"metadata": {"component": component, **metadata}, "vars": variables}


def dns(records=None, **metadata):
    return instance(
        "dns",
        {
            "zones": {
                "main": {"name": DOMAIN},
                "services": {"name": f"services.{DOMAIN}", "parent_zone": "main"},
            },
            "records": records or {},
        },
        **metadata,
    )


def acm(zone_id, *domains, method="DNS"):
    certs = {
        f"cert{i}": {"domain_name": domain, "subject_alternative_names": sans, "validation_method": method}
        for i, (domain, sans) in enumerate(domains)
    }
    return instance("acm", {"zone_id": zone_id, "dns_domains": certs})


def stacks_with(**components):
    return {"s1": {"components": {"terraform": {"network/main": dns(), **components}}}}


class CheckDomainsTest(unittest.TestCase):
    def assert_result(self, stacks, errors=(), warnings=()):
        got_errors, got_warnings = check_domains.check(stacks)
        self.assertEqual(len(got_errors), len(errors), got_errors)
        for error, fragment in zip(got_errors, errors):
            self.assertIn(fragment, error)
        self.assertEqual(len(got_warnings), len(warnings), got_warnings)
        for warning, fragment in zip(got_warnings, warnings):
            self.assertIn(fragment, warning)

    def test_in_zone(self):
        self.assertTrue(check_domains.in_zone(DOMAIN, DOMAIN))
        self.assertTrue(check_domains.in_zone(f"*.{DOMAIN}", DOMAIN))
        self.assertTrue(check_domains.in_zone(f"Api.{DOMAIN}.", DOMAIN + "."))
        self.assertFalse(check_domains.in_zone(f"api{DOMAIN}", DOMAIN))
        self.assertFalse(check_domains.in_zone("fnx.example.com", DOMAIN))

    def test_dns_records_inside_their_zone_pass(self):
        records = {
            "apex": {"zone_name": "main", "name": DOMAIN},
            "www": {"zone_name": "main", "name": f"www.{DOMAIN}"},
            "api": {"zone_name": "services", "name": f"api.services.{DOMAIN}."},
        }
        self.assert_result({"s1": {"components": {"terraform": {"network/main": dns(records)}}}})

    def test_dns_record_outside_its_zone_fails(self):
        records = {"www": {"zone_name": "services", "name": f"www.{DOMAIN}"}}
        stacks = {"s1": {"components": {"terraform": {"network/main": dns(records)}}}}
        self.assert_result(stacks, errors=["record www (zone services): www.staging.fnx.example.com is not in its zone (services."])

    def test_dns_record_with_unknown_zone_fails(self):
        records = {"www": {"zone_name": "nope", "name": f"www.{DOMAIN}"}}
        stacks = {"s1": {"components": {"terraform": {"network/main": dns(records)}}}}
        self.assert_result(stacks, errors=["zone_name 'nope' is not a key of zones"])

    def test_acm_names_inside_referenced_zone_pass(self):
        cert = acm("!terraform.state network/main .zone_ids.main", (f"*.{DOMAIN}", [DOMAIN, f"*.api.{DOMAIN}"]))
        self.assert_result(stacks_with(**{"acm/main": cert}))

    def test_acm_two_certificates_are_each_checked(self):
        cert = acm(
            "!terraform.state network/main .zone_ids.services",
            (f"api.services.{DOMAIN}", []),
            (f"assets.{DOMAIN}", []),
        )
        self.assert_result(
            stacks_with(**{"acm/services": cert}),
            errors=["certificate cert1: assets.staging.fnx.example.com is not in its zone ("],
        )

    def test_acm_double_prefixed_domain_fails(self):
        # The pre-fix staging shape: domain_name staging.example.com behind an
        # extra "staging." prefix, validated in the staging.fnx.example.com zone.
        cert = acm(
            "!terraform.state network/main .zone_ids.main",
            ("*.staging.staging.example.com", ["staging.staging.example.com"]),
        )
        self.assert_result(
            stacks_with(**{"acm/main": cert}),
            errors=["*.staging.staging.example.com is not in", "staging.staging.example.com is not in"],
        )

    def test_email_validated_certificate_is_not_checked(self):
        cert = acm("!terraform.state network/main .zone_ids.main", ("other.example.org", []), method="EMAIL")
        self.assert_result(stacks_with(**{"acm/main": cert}))

    def test_quoted_and_cross_stack_references_resolve(self):
        quoted = acm("!terraform.state network/main '.zone_ids[\"main\"]'", (f"*.{DOMAIN}", []))
        cross = acm("!terraform.state network/main s1 .zone_ids.services", (f"x.{DOMAIN}", []))
        stacks = stacks_with(**{"acm/main": quoted})
        stacks["s2"] = {"components": {"terraform": {"acm/cross": cross}}}
        self.assert_result(stacks, errors=["s2: acm/cross certificate cert0: x.staging.fnx.example.com is not in"])

    def test_unresolvable_references_fail(self):
        for zone_id, fragment in [
            ("!terraform.state network/main .zone_ids", "does not read .zone_ids.<key>"),
            ("!terraform.state network/main .zone_ids.nope", "has no zone 'nope'"),
            ("!terraform.state network/nope .zone_ids.main", "which does not exist"),
            ("!terraform.state acm/other .zone_ids.main", "not a dns instance"),
        ]:
            with self.subTest(zone_id=zone_id):
                stacks = stacks_with(**{"acm/main": acm(zone_id, (f"*.{DOMAIN}", []))})
                stacks["s1"]["components"]["terraform"]["acm/other"] = acm("Z1", ("a.example.com", []))
                self.assert_result(
                    stacks, errors=[fragment], warnings=["acm/other: zone_id 'Z1' is a literal zone id"]
                )

    def test_literal_zone_id_is_a_warning(self):
        cert = acm("Z1234567890EXAMPLE", ("*.example.com", []))
        self.assert_result(stacks_with(**{"acm/main": cert}), warnings=["is a literal zone id"])

    def test_apigateway_domain_is_checked_against_its_zone(self):
        good = instance("apigateway", {"domain_name": f"api.{DOMAIN}", "zone_id": "!terraform.state network/main .zone_ids.main"})
        bad = instance("apigateway", {"domain_name": "api.example.com", "zone_id": "!terraform.state network/main .zone_ids.main"})
        no_zone = instance("apigateway", {"domain_name": "api.example.com", "zone_id": None})
        self.assert_result(
            stacks_with(**{"apigateway/good": good, "apigateway/bad": bad, "apigateway/none": no_zone}),
            errors=["apigateway/bad domain_name: api.example.com is not in its zone (staging.fnx.example.com)"],
        )

    def test_name_owned_by_a_more_specific_public_zone_fails(self):
        # data.services.<domain> is the apex of its own zone: an ACM validation
        # record for it in the services zone is shadowed once data is delegated.
        services = dns()
        services["vars"]["zones"]["data"] = {"name": f"data.services.{DOMAIN}", "parent_zone": "services"}
        cert = acm(
            "!terraform.state network/main .zone_ids.services",
            (f"*.services.{DOMAIN}", [f"api.services.{DOMAIN}", f"data.services.{DOMAIN}"]),
        )
        stacks = {"s1": {"components": {"terraform": {"network/main": services, "acm/services": cert}}}}
        self.assert_result(
            stacks,
            errors=[
                "data.services.staging.fnx.example.com is in services.staging.fnx.example.com but belongs to "
                "the more specific public zone data.services.staging.fnx.example.com (network/main zone data)"
            ],
        )

    def test_record_in_a_private_zone_is_not_shadowed_by_a_public_one(self):
        zones = {
            "main": {"name": DOMAIN},
            "internal": {"name": f"internal.{DOMAIN}", "vpc_associations": ["vpc-1"]},
            "public_db": {"name": f"db.internal.{DOMAIN}", "parent_zone": "main"},
        }
        records = {
            "db": {"zone_name": "internal", "name": f"db.internal.{DOMAIN}"},
            "shadowed": {"zone_name": "main", "name": f"x.db.internal.{DOMAIN}"},
        }
        stacks = {"s1": {"components": {"terraform": {
            "network/main": instance("dns", {"zones": zones, "records": records}),
        }}}}
        self.assert_result(stacks, errors=["record shadowed (zone main): x.db.internal.staging.fnx.example.com is in"])

    # --- delegation -------------------------------------------------------

    @staticmethod
    def two_instances(ns_records=None, child_zone=None):
        """network/main (zone main = DOMAIN) and network/services (zone services below it)."""
        main = instance("dns", {"zones": {"main": {"name": DOMAIN}}, "records": ns_records or {}})
        services = instance(
            "dns", {"zones": {"services": child_zone or {"name": f"services.{DOMAIN}"}}, "records": {}}
        )
        return {"s1": {"components": {"terraform": {"network/main": main, "network/services": services}}}}

    def ns(self, records, name=f"services.{DOMAIN}"):
        return {"services_delegation": {"zone_name": "main", "name": name, "type": "NS", "records": records}}

    def test_subzone_delegated_by_ns_record_passes(self):
        stacks = self.two_instances(self.ns("!terraform.state network/services .zone_name_servers.services"))
        self.assert_result(stacks)

    def test_undelegated_subzone_fails(self):
        self.assert_result(
            self.two_instances(),
            errors=[
                "network/services zone services (services.staging.fnx.example.com) is not delegated from its parent "
                "zone staging.fnx.example.com (network/main zone main): add an NS record there whose records are "
                "`!terraform.state network/services .zone_name_servers.services`"
            ],
        )

    def test_ns_record_must_read_the_child_zones_name_servers(self):
        for records in (
            ["ns-1.awsdns-01.org"],
            "!terraform.state network/services .zone_name_servers.other",
            "!terraform.state network/services .zone_ids.services",
            "!terraform.state network/main .zone_name_servers.main",
        ):
            with self.subTest(records=records):
                self.assert_result(
                    self.two_instances(self.ns(records)),
                    errors=["NS record network/main services_delegation must read"],
                )

    def test_ns_record_for_another_name_does_not_delegate(self):
        stacks = self.two_instances(
            self.ns("!terraform.state network/services .zone_name_servers.services", name=f"x.{DOMAIN}")
        )
        self.assert_result(stacks, errors=["is not delegated from its parent zone"])

    def test_parent_zone_must_name_the_closest_public_parent(self):
        wrong = {"name": f"services.{DOMAIN}", "parent_zone": "main"}  # main is in network/main
        self.assert_result(
            self.two_instances(child_zone=wrong),
            errors=["parent_zone 'main', but its parent zone is staging.fnx.example.com (network/main zone main)"],
        )
        top = instance("dns", {"zones": {"main": {"name": DOMAIN, "parent_zone": "x"}}})
        self.assert_result(
            {"s1": {"components": {"terraform": {"network/main": top}}}},
            errors=["parent_zone 'x' but no public zone of the stack is above it"],
        )

    def test_private_subzone_needs_no_delegation(self):
        stacks = self.two_instances(child_zone={"name": f"services.{DOMAIN}", "vpc_associations": ["vpc-1"]})
        self.assert_result(stacks)

    # --- robustness -------------------------------------------------------

    def test_null_entries_are_skipped(self):
        network = instance("dns", {"zones": {"main": {"name": DOMAIN}, "gone": None}, "records": {"x": None}})
        cert = instance("acm", {"zone_id": "!terraform.state network/main .zone_ids.main", "dns_domains": {"c": None}})
        stacks = {"s1": {"components": {"terraform": {"network/main": network, "acm/main": cert}}}}
        self.assert_result(stacks)

    def test_zone_id_reading_a_disabled_dns_instance_fails(self):
        stacks = stacks_with(**{"acm/main": acm("!terraform.state network/off .zone_ids.main", (f"*.{DOMAIN}", []))})
        stacks["s1"]["components"]["terraform"]["network/off"] = dns(enabled=False)
        self.assert_result(stacks, errors=["reads network/off, which is abstract or disabled"])

    # --- apigateway certificates -----------------------------------------

    def api_stacks(self, domain, certificate_arn="!terraform.state acm/main .certificate_arns.cert0"):
        cert = acm("!terraform.state network/main .zone_ids.main", (f"*.{DOMAIN}", [DOMAIN]))
        api = instance("apigateway", {"domain_name": domain, "certificate_arn": certificate_arn})
        return stacks_with(**{"acm/main": cert, "apigateway/main": api})

    def test_covers(self):
        self.assertTrue(check_domains.covers("*.example.com", "api.example.com"))
        self.assertTrue(check_domains.covers("api.example.com", "API.example.com."))
        self.assertFalse(check_domains.covers("*.example.com", "a.b.example.com"))
        self.assertFalse(check_domains.covers("*.example.com", "example.com"))
        self.assertFalse(check_domains.covers("example.com", "api.example.com"))

    def test_certificate_covering_the_domain_passes(self):
        self.assert_result(self.api_stacks(f"api.{DOMAIN}"))  # the wildcard
        self.assert_result(self.api_stacks(DOMAIN))  # the apex SAN

    def test_certificate_not_covering_the_domain_fails(self):
        self.assert_result(
            self.api_stacks(f"api.services.{DOMAIN}"),
            errors=[
                "apigateway/main: certificate acm/main cert0 (*.staging.fnx.example.com, staging.fnx.example.com) "
                "does not cover domain_name api.services.staging.fnx.example.com"
            ],
        )

    def test_certificate_reference_must_resolve(self):
        for arn, fragment in [
            ("!terraform.state acm/main .certificate_arns.nope", "acm/main has no certificate 'nope'"),
            ("!terraform.state acm/none .certificate_arns.cert0", "which does not exist"),
            ("!terraform.state network/main .certificate_arns.cert0", "not a acm instance"),
            ("!terraform.state acm/main .certificate_arns", "does not read .certificate_arns.<key>"),
        ]:
            with self.subTest(arn=arn):
                self.assert_result(self.api_stacks(f"api.{DOMAIN}", arn), errors=[fragment])

    def test_literal_certificate_arn_is_a_warning(self):
        self.assert_result(
            self.api_stacks(f"api.{DOMAIN}", "arn:aws:acm:eu-west-2:1:certificate/x"),
            warnings=[
                "apigateway/main: certificate_arn 'arn:aws:acm:eu-west-2:1:certificate/x' is a literal certificate ARN; "
                "domain_name api.staging.fnx.example.com is not checked against it"
            ],
        )

    def test_no_certificate_arn_is_no_warning(self):
        for arn in (None, ""):
            with self.subTest(arn=arn):
                self.assert_result(self.api_stacks(f"api.{DOMAIN}", arn))

    def test_missing_zone_message_names_zone_id_once(self):
        stacks = stacks_with(**{"acm/main": acm("!terraform.state network/main .zone_ids.nope", (f"*.{DOMAIN}", []))})
        errors, _ = check_domains.check(stacks)
        self.assertEqual(
            errors, ["s1: acm/main: zone_id reads network/main .zone_ids.nope, but network/main has no zone 'nope'"]
        )

    def test_abstract_and_disabled_instances_are_skipped(self):
        outside = {"www": {"zone_name": "main", "name": "www.example.org"}}
        stacks = {
            "s1": {
                "components": {
                    "terraform": {
                        "dns": dns(outside, type="abstract"),
                        "network/off": dns(outside, enabled=False),
                    }
                }
            }
        }
        self.assert_result(stacks)


if __name__ == "__main__":
    unittest.main()
