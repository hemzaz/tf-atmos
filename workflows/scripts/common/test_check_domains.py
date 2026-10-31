"""Tests for check-domains.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import unittest
from unittest import mock

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

    def test_ds_record_at_a_delegated_subzone_apex_passes(self):
        # DNSSEC: the child's DS record lives in the parent, at the delegation point.
        records = self.ns("!terraform.state network/services .zone_name_servers.services")
        ds = {"zone_name": "main", "name": f"services.{DOMAIN}", "type": "DS", "records": ["1 13 2 AB"]}
        self.assert_result(self.two_instances({**records, "services_ds": ds}))
        a = {**ds, "type": "A"}
        self.assert_result(
            self.two_instances({**records, "services_a": a}), errors=["belongs to the more specific public zone"]
        )

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
            self.api_stacks(f"api.{DOMAIN}", "arn:aws:acm:us-east-1:1:certificate/x"),
            warnings=[
                "apigateway/main: certificate_arn 'arn:aws:acm:us-east-1:1:certificate/x' is a literal certificate ARN; "
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

    # A DR certificate with process_domain_validation_options false (the
    # fnx-ue2-prod acm/main shape) waits on its primary's record.
    @staticmethod
    def dr_stacks(primary_sans=(DOMAIN, f"*.api.{DOMAIN}"), depends=True, dr_account="prod"):
        primary = acm("!terraform.state network/main .zone_ids.main", (f"*.{DOMAIN}", list(primary_sans)))
        primary["settings"] = {"environment": {"account": "prod"}}
        dr = instance("acm", {"zone_id": "", "dns_domains": {
            "api": {"domain_name": f"api.{DOMAIN}", "validation_method": "DNS", "process_domain_validation_options": False},
        }})
        dr["settings"] = {"environment": {"account": dr_account}}
        if depends:
            dr["dependencies"] = {"components": [{"component": "acm/main", "stack": "s1"}]}
        stacks = stacks_with(**{"acm/main": primary})
        stacks["s2"] = {"components": {"terraform": {"acm/main": dr}}}
        return stacks

    def test_unprocessed_certificate_covered_by_dependency_passes(self):
        self.assert_result(self.dr_stacks())

    def test_unprocessed_certificate_without_the_san_fails(self):
        self.assert_result(
            self.dr_stacks(primary_sans=(DOMAIN,)),
            errors=["s2: acm/main: certificate api sets process_domain_validation_options: false, but no processed DNS certificate"],
        )

    def test_unprocessed_certificate_without_the_dependency_fails(self):
        self.assert_result(
            self.dr_stacks(depends=False),
            errors=["certificate api sets process_domain_validation_options: false"],
        )

    def test_unprocessed_certificate_depending_on_another_account_fails(self):
        self.assert_result(
            self.dr_stacks(dr_account="prod-eu"),
            errors=["depends on s1 acm/main, in account 'prod', not 'prod-eu'", "certificate api sets process_domain_validation_options: false"],
        )

    def test_unprocessed_certificate_without_an_account_fails(self):
        stacks = self.dr_stacks()
        del stacks["s2"]["components"]["terraform"]["acm/main"]["settings"]
        self.assert_result(
            stacks,
            errors=["s2: acm/main: has no settings.environment.account", "certificate api sets process_domain_validation_options: false"],
        )

    def test_unprocessed_certificate_depending_on_an_instance_without_an_account_fails(self):
        stacks = self.dr_stacks()
        del stacks["s1"]["components"]["terraform"]["acm/main"]["settings"]
        self.assert_result(
            stacks,
            errors=["depends on s1 acm/main, which has no settings.environment.account", "certificate api sets process_domain_validation_options: false"],
        )

    def test_both_instances_without_an_account_fail(self):
        # None == None must not pass as "the same account".
        stacks = self.dr_stacks()
        for name in ("s1", "s2"):
            del stacks[name]["components"]["terraform"]["acm/main"]["settings"]
        self.assert_result(
            stacks,
            errors=[
                "s2: acm/main: has no settings.environment.account",
                "depends on s1 acm/main, which has no settings.environment.account",
                "certificate api sets process_domain_validation_options: false",
            ],
        )

    def test_unprocessed_certificate_outside_the_zone_is_not_placed_but_still_checked(self):
        # One acm instance, a processed certificate in zone_id and an unprocessed one whose name is
        # outside it: zoned_names skips the unprocessed one (it writes no record), so no placement
        # error, while borrowed_validation_errors still requires a dependency that carries it.
        mixed = acm("!terraform.state network/main .zone_ids.main", (f"*.{DOMAIN}", [DOMAIN]))
        mixed["settings"] = {"environment": {"account": "prod"}}
        mixed["vars"]["dns_domains"]["other"] = {
            "domain_name": "api.other.example.org", "validation_method": "DNS", "process_domain_validation_options": False,
        }
        self.assert_result(
            stacks_with(**{"acm/main": mixed}),
            errors=["s1: acm/main: certificate other sets process_domain_validation_options: false"],
        )
        carrier = acm("", ("api.other.example.org", []))
        carrier["settings"] = {"environment": {"account": "prod"}}
        mixed["dependencies"] = {"components": [{"component": "acm/carrier"}]}
        self.assert_result(stacks_with(**{"acm/main": mixed, "acm/carrier": carrier}))

    def test_unprocessed_certificates_do_not_cover_each_other(self):
        stacks = self.dr_stacks()
        primary = stacks["s1"]["components"]["terraform"]["acm/main"]
        primary["vars"]["dns_domains"]["cert0"]["process_domain_validation_options"] = False
        primary["dependencies"] = {"components": [{"component": "acm/main", "stack": "s2"}]}
        self.assert_result(stacks, errors=["s1: acm/main: certificate cert0", "s1: acm/main: certificate cert0", "s1: acm/main: certificate cert0", "s2: acm/main: certificate api"])


SVC = "fnx-svc.example.net"
DEV = f"dev.{SVC}"
DELEGATED_ID = "!terraform.state dns-delegated .default_dns_zone_id"


def cp_stacks(**dev_extra):
    """E6b's target: an aws-dns-primary service domain, dev delegated from it (Cloud Posse
    aws-dns-delegated), the house dns writing into the delegated zone through external_zones."""
    main = instance("dns", {
        "external_zones": {"delegated": {"zone_id": DELEGATED_ID}},
        "records": {
            "services_delegation": {"zone_name": "delegated", "name": f"services.{DEV}", "type": "NS",
                                    "records": "!terraform.state network/services .zone_name_servers.services"},
            "www": {"zone_name": "delegated", "name": f"www.{DEV}", "type": "CNAME"},
        },
    })
    dev = {
        "dns-delegated": instance("aws-dns-delegated", {"zone_config": [{"subdomain": "dev", "zone_name": SVC}]}),
        "network/services": instance("dns", {"zones": {"services": {"name": f"services.{DEV}"}}}),
        "network/main": main,
        "acm/main": acm(DELEGATED_ID, (DEV, [f"*.{DEV}"])),
        **dev_extra,
    }
    return {
        "net": {"components": {"terraform": {"dns-primary": instance("aws-dns-primary", {"domain_names": [SVC]})}}},
        "dev": {"components": {"terraform": dev}},
    }


class VendoredDnsKindsTest(unittest.TestCase):
    assert_result = CheckDomainsTest.assert_result

    def test_target_layout_passes(self):
        self.assert_result(cp_stacks())

    def test_delegated_parent_held_nowhere_fails(self):
        stacks = cp_stacks()
        stacks["net"]["components"]["terraform"]["dns-primary"]["metadata"]["enabled"] = False
        self.assert_result(stacks, errors=[f"dev: dns-delegated zone dev ({DEV}) writes its NS record into zone_name {SVC}, which no deployable"])

    def test_delegated_below_a_closer_zone_of_its_stack_fails(self):
        stacks = cp_stacks()
        stacks["dev"]["components"]["terraform"]["dns-delegated"]["vars"]["zone_config"].append({"subdomain": "a.dev", "zone_name": SVC})
        self.assert_result(stacks, errors=[f"zone a.dev (a.{DEV}) writes its NS record into {SVC}, but its closest parent zone in the stack is {DEV}"])

    def test_delegated_without_root_delegation_below_a_stack_zone_fails(self):
        child = instance("aws-dns-delegated", {"zone_config": [{"subdomain": "x", "zone_name": DEV}], "create_root_delegation": False})
        self.assert_result(cp_stacks(**{"child": child}), errors=[f"child zone x (x.{DEV}) is below {DEV} (dns-delegated zone dev) but sets create_root_delegation: false"])

    def test_primary_below_a_stack_zone_fails(self):
        nested = instance("aws-dns-primary", {"domain_names": [f"p.{DEV}"]})
        self.assert_result(cp_stacks(**{"nested": nested}), errors=[f"an aws-dns-primary zone is a root, but sits below {DEV}"])

    def test_private_delegated_zone_is_not_public(self):
        private = instance("aws-dns-delegated", {"zone_config": [{"subdomain": "x", "zone_name": "nowhere.example"}], "dns_private_zone_enabled": True})
        self.assert_result(cp_stacks(**{"private": private}))

    def test_record_outside_its_external_zone_fails(self):
        stacks = cp_stacks()
        records = stacks["dev"]["components"]["terraform"]["network/main"]["vars"]["records"]
        records["www"]["name"] = "www.elsewhere.example.org"
        records["bad"] = {"zone_name": "nope", "name": f"x.{DEV}"}
        self.assert_result(stacks, errors=[
            "record bad: zone_name 'nope' is not a key of zones or external_zones",
            f"record www (zone delegated): www.elsewhere.example.org is not in its zone ({DEV})",
        ])

    def test_external_zone_by_name_and_literal_id(self):
        stacks = cp_stacks()
        main = stacks["dev"]["components"]["terraform"]["network/main"]["vars"]
        main["external_zones"] = {"delegated": {"name": DEV}, "lit": {"zone_id": "Z0123456789ABCDEFGHIJ"}}
        main["records"]["lit"] = {"zone_name": "lit", "name": "a.example.org"}
        self.assert_result(stacks, warnings=["record lit: external_zones.lit.zone_id is a literal zone id"])

    def test_subzone_not_delegated_through_the_external_zone_fails(self):
        stacks = cp_stacks()
        del stacks["dev"]["components"]["terraform"]["network/main"]["vars"]["records"]["services_delegation"]
        self.assert_result(stacks, errors=[f"zone services (services.{DEV}) is not delegated from its parent zone {DEV} (dns-delegated zone dev)"])

    def test_acm_reading_default_dns_zone_id(self):
        self.assert_result(cp_stacks(**{"acm/main": acm(DELEGATED_ID, ("api.other.example.org", []))}),
                           errors=[f"certificate cert0: api.other.example.org is not in its zone ({DEV})"])
        stacks = cp_stacks()
        stacks["dev"]["components"]["terraform"]["dns-delegated"]["vars"]["zone_config"] = []
        self.assert_result(stacks, errors=[
            "acm/main: zone_id reads dns-delegated .default_dns_zone_id, but dns-delegated has no zone_config entry",
            "network/main record services_delegation: external_zones.delegated.zone_id reads dns-delegated",
            "network/main record www: external_zones.delegated.zone_id reads dns-delegated",
        ])


    def test_duplicate_zone_names_fail(self):
        house = instance("dns", {"zones": {"dup": {"name": DEV}}})
        self.assert_result(cp_stacks(**{"old/main": house}), errors=[f"dev: public zone {DEV} is held twice: old/main zone dup, dns-delegated zone dev"])
        stacks = cp_stacks()
        stacks["staging"] = {"components": {"terraform": {"dns-delegated": stacks["dev"]["components"]["terraform"]["dns-delegated"]}}}
        self.assert_result(stacks, errors=[f"dev: aws-dns-delegated zone {DEV} is held by stacks dev, staging"])
        stacks["staging"]["components"]["terraform"]["dns-delegated"] = dict(
            stacks["dev"]["components"]["terraform"]["dns-delegated"], settings={"context": {"stage": "fixtures"}})
        self.assert_result(stacks)

    def test_bad_reads_and_names(self):
        stacks = cp_stacks(**{"acm/main": acm("!terraform.state dns-delegatd .default_dns_zone_id", (DEV, []))})
        self.assert_result(stacks, errors=["acm/main: zone_id `!terraform.state dns-delegatd .default_dns_zone_id` reads dns-delegatd in dev, which does not exist"])
        stacks = cp_stacks()
        stacks["dev"]["components"]["terraform"]["dns-delegated"]["vars"]["dns_private_zone_enabled"] = "true"
        errors, _ = check_domains.check(stacks)
        self.assertIn("acm/main: zone_id reads dns-delegated .default_dns_zone_id, a private zone", errors[0])
        stacks = cp_stacks()
        stacks["dev"]["components"]["terraform"]["network/main"]["vars"]["external_zones"]["delegated"] = {"name": "dev.fnx-svc.exmaple.net"}
        errors, _ = check_domains.check(stacks)
        self.assertIn("external_zones.delegated.name dev.fnx-svc.exmaple.net is no deployable public zone of any stack", errors[-1])

    def test_quoted_false_create_root_delegation_writes_no_ns(self):
        child = instance("aws-dns-delegated", {"zone_config": [{"subdomain": "x", "zone_name": DEV}], "create_root_delegation": "false"})
        self.assert_result(cp_stacks(child=child), errors=["but sets create_root_delegation: false"])

class LogPolicyQuotaTest(unittest.TestCase):
    """CloudWatch Logs: 10 account-scoped resource policies per region and account."""

    @staticmethod
    def logged(account, stage="dev", **variables):
        zones = {"main": {"name": f"{account}.example.org", "enable_query_logging": True}}
        found = instance("dns", {"zones": zones, **variables})
        found["settings"] = {"environment": {"account": account}, "context": {"stage": stage}}
        return found

    def stacks(self, count, account="dev", stage="dev", **extra):
        held = {f"q{i}": self.logged(account, stage) for i in range(count)}
        return {"s1": {"components": {"terraform": {**held, **extra}}}}

    def test_ten_policies_pass(self):
        self.assertEqual(check_domains.log_policy_errors(self.stacks(10)), [])

    def test_eleven_policies_in_one_account_fail(self):
        errors = check_domains.log_policy_errors(self.stacks(11))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("account dev region us-east-1: 11 CloudWatch Logs resource policies", errors[0])

    def test_counted_across_stacks_by_account(self):
        stacks = self.stacks(6)
        stacks["s2"] = self.stacks(5)["s1"]
        self.assertEqual(len(check_domains.log_policy_errors(stacks)), 1)
        stacks["s2"] = self.stacks(5, account="staging")["s1"]
        self.assertEqual(check_domains.log_policy_errors(stacks), [])

    def test_waf_counts_in_its_region_and_cloudfront_in_us_east_1(self):
        def waf(scope, **variables):
            found = instance("waf", {"scope": scope, "region": "us-east-2", "enable_logging": True, **variables})
            found["settings"] = {"environment": {"account": "dev"}, "context": {"stage": "dev"}}
            return found
        self.assertEqual(len(check_domains.log_policy_errors(self.stacks(10, w=waf("CLOUDFRONT")))), 1)
        self.assertEqual(check_domains.log_policy_errors(self.stacks(10, w=waf("REGIONAL"))), [])
        quiet = waf("CLOUDFRONT", manage_log_resource_policy=False)
        self.assertEqual(check_domains.log_policy_errors(self.stacks(10, w=quiet)), [])
        off = waf("CLOUDFRONT", enabled=False)
        self.assertEqual(check_domains.log_policy_errors(self.stacks(10, w=off)), [])

    def test_waf_without_enable_logging_counts_by_its_default(self):
        found = instance("waf", {"scope": "CLOUDFRONT", "region": "us-east-2"})
        found["settings"] = {"environment": {"account": "dev"}, "context": {"stage": "dev"}}
        errors = check_domains.log_policy_errors(self.stacks(10, w=found))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("account dev region us-east-1: 11 CloudWatch Logs resource policies", errors[0])

    @staticmethod
    def mapped(found, **account_map):
        found["settings"]["account_map"] = {"full_account_map": account_map}
        return found

    def test_dns_account_zones_count_in_the_role_accounts_name(self):
        role = "arn:aws:iam::222222222222:role/dns"
        remote = self.logged("dev", multi_account_dns_delegation=True, dns_account_assume_role_arn=role)
        accounts = {"222222222222": {"network"}}
        self.assertEqual(check_domains.log_policies("s1", "n", remote, accounts), ([("network", "us-east-1")], []))
        # Counted with the network account's own policies, from the account map.
        stacks = self.stacks(10, account="network")
        stacks["s2"] = {"components": {"terraform": {"d": self.mapped(remote, dev="111111111111", network="222222222222")}}}
        errors = check_domains.log_policy_errors(stacks)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("account network region us-east-1: 11", errors[0])

    def test_shared_placeholder_id_counts_in_each_account(self):
        role = "arn:aws:iam::123456789012:role/dns"
        remote = self.logged("dev", multi_account_dns_delegation=True, dns_account_assume_role_arn=role)
        accounts = {"123456789012": {"network", "root"}}
        self.assertEqual(
            check_domains.log_policies("s1", "n", remote, accounts),
            ([("network", "us-east-1"), ("root", "us-east-1")], []),
        )

    def test_unknown_role_account_id_fails(self):
        role = "arn:aws:iam::999999999999:role/dns"
        remote = self.logged("dev", multi_account_dns_delegation=True, dns_account_assume_role_arn=role)
        errors = check_domains.log_policy_errors({"s1": {"components": {"terraform": {"d": remote}}}})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("names account id 999999999999, which no stack", errors[0])

    def test_dns_account_zones_without_a_role_count_in_the_own_account(self):
        moved = self.logged("dev", multi_account_dns_delegation=True)
        self.assertEqual(check_domains.log_policies("s1", "n", moved, {}), ([("dev", "us-east-1")], []))
        external = {"e": {"name": "x.example.org", "enable_query_logging": True, "dns_account": True}}
        both = self.logged("dev", external_zones=external)
        # Two policy resources (the local one and the aws.dns_account one), both in dev.
        self.assertEqual(
            check_domains.log_policies("s1", "n", both, {}), ([("dev", "us-east-1"), ("dev", "us-east-1")], [])
        )

    def test_unlogged_private_disabled_and_fixture_instances_do_not_count(self):
        private = {"p": {"name": "p.example.org", "enable_query_logging": True, "vpc_associations": ["v"]}}
        self.assertEqual(check_domains.log_policies("s1", "n", instance("dns", {"zones": private}), {}), ([], []))
        self.assertEqual(check_domains.log_policy_errors(self.stacks(11, stage="fixtures")), [])
        disabled = self.logged("dev")
        disabled["metadata"]["enabled"] = False
        self.assertEqual(check_domains.log_policy_errors(self.stacks(10, extra=disabled)), [])

    def test_check_reports_the_quota(self):
        errors, _ = check_domains.check(self.stacks(11))
        self.assertTrue(any("CloudWatch Logs resource policies" in e for e in errors), errors)

    def test_policy_names_collide_per_account(self):
        # Pinned to one name in two accounts (dev, staging): distinct policies.
        apart = {"s1": {"components": {"terraform": {"m": self.logged("dev", query_logging_name="ue1-main")}}},
                 "s2": {"components": {"terraform": {"m": self.logged("staging", query_logging_name="ue1-main")}}}}
        self.assertEqual(check_domains.log_policy_name_errors(apart), [])
        # The same name twice in one account, pinned or derived from the same first zone.
        clash = self.stacks(1, extra=self.logged("dev", query_logging_name="dev-example-org"))
        errors = check_domains.log_policy_name_errors(clash)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("account dev: route53-query-logging-dev-example-org", errors[0])
        unpinned = self.logged("dev")
        unpinned["vars"]["zones"]["main"]["enable_query_logging"] = False
        self.assertEqual(check_domains.log_policy_name_errors(self.stacks(1, extra=unpinned)), [])


NET_ID = "111111111111"
ROLE = f"arn:aws:iam::{NET_ID}:role/fnx-ue1-network-dns-delegation"


def signed_stacks():
    """E6b-inst's target: network signs and logs the apex, dev its delegated zone, aws.primary's role allows it."""
    off = {"account_map_enabled": False}
    role = instance("aws-iam-role", {
        **off, "name": "dns-delegation",
        "context": {"tenant": "fnx", "environment": "ue1", "stage": "network", "label_order": ["tenant", "environment", "stage", "name"]},
        "policy_statements": {"WriteDelegations": {"effect": "Allow", "condition": {
            "ForAllValues:StringEquals": {check_domains.RECORD_NAMES_KEY: [DEV, f"staging.{SVC}"]}}}},
    })
    role["settings"] = {"environment": {"account_id": NET_ID}}
    signer = lambda key, name: instance("dns", {"dnssec_enabled": True, "external_zones": {
        key: {"name": name, "dnssec_enabled": True, "enable_query_logging": True}}})
    delegated = instance("aws-dns-delegated", {**off, "zone_config": [{"subdomain": "dev", "zone_name": SVC}],
                                               "account_map": {"iam_role_arn_templates": {"dns-delegation": ROLE}}})
    return {
        "net": {"components": {"terraform": {
            "aws-dns-primary": instance("aws-dns-primary", {**off, "domain_names": [SVC]}),
            "aws-iam-role/dns-delegation": role,
            "network/primary": signer("apex", SVC),
        }}},
        "dev": {"components": {"terraform": {"aws-dns-delegated": delegated, "network/main": signer("main", DEV)}}},
    }


class VendoredSigningTest(unittest.TestCase):
    """The #449 allowlist reason (CKV2_AWS_38/39: the house dns signs and logs them), enforced."""

    def errors(self, stacks):
        return check_domains.vendored_dns_errors(stacks)

    def test_target_passes_and_disabled_instances_are_skipped(self):
        self.assertEqual(self.errors(signed_stacks()), [])
        stacks = signed_stacks()
        del stacks["dev"]["components"]["terraform"]["network/main"]
        stacks["dev"]["components"]["terraform"]["aws-dns-delegated"]["metadata"]["enabled"] = False
        self.assertEqual(self.errors(stacks), [])

    def test_unlisted_unsigned_or_unlogged_zone_fails(self):
        stacks = signed_stacks()
        del stacks["net"]["components"]["terraform"]["network/primary"]
        errors = self.errors(stacks)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(f"net: aws-dns-primary: aws-dns-primary zone {SVC} is not an external_zones entry", errors[0])
        for where, key in (("entry", "enable_query_logging"), ("entry", "dnssec_enabled"), ("instance", "dnssec_enabled")):
            with self.subTest(f"{where} {key}"):
                stacks = signed_stacks()
                main = stacks["dev"]["components"]["terraform"]["network/main"]["vars"]
                (main["external_zones"]["main"] if where == "entry" else main)[key] = False
                errors = self.errors(stacks)
                self.assertEqual(len(errors), 1, errors)
                self.assertIn("network/main external_zones.main must set dnssec_enabled and enable_query_logging", errors[0])

    def test_listing_by_zone_id_reading_the_delegated_zone_passes(self):
        stacks = signed_stacks()
        entry = stacks["dev"]["components"]["terraform"]["network/main"]["vars"]["external_zones"]["main"]
        entry.pop("name")
        entry["zone_id"] = "!terraform.state aws-dns-delegated .default_dns_zone_id"
        self.assertEqual(self.errors(stacks), [])

    def test_account_map_lookup_fails(self):
        stacks = signed_stacks()
        del stacks["net"]["components"]["terraform"]["aws-iam-role/dns-delegation"]["vars"]["account_map_enabled"]
        errors = self.errors(stacks)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("aws-iam-role/dns-delegation: account_map_enabled must be false", errors[0])

    def test_main_runs_it(self):
        stacks = signed_stacks()
        stacks["net"]["components"]["terraform"]["network/primary"]["vars"]["dnssec_enabled"] = False
        with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(stacks))), contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(check_domains.main(), 1)
        self.assertIn("external_zones.apex must set dnssec_enabled", out.getvalue())

    def test_wrong_role_or_unallowed_name_fails(self):
        stacks = signed_stacks()
        templates = stacks["dev"]["components"]["terraform"]["aws-dns-delegated"]["vars"]["account_map"]["iam_role_arn_templates"]
        templates["dns-delegation"] = ROLE.replace("network-dns", "network-dnz")
        errors = self.errors(stacks)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("is not the ARN of a deployable aws-iam-role instance", errors[0])
        stacks = signed_stacks()
        stacks["dev"]["components"]["terraform"]["aws-dns-delegated"]["vars"]["zone_config"][0]["subdomain"] = "qa"
        stacks["dev"]["components"]["terraform"]["network/main"]["vars"]["external_zones"]["main"]["name"] = f"qa.{SVC}"
        errors = self.errors(stacks)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(f"zone qa.{SVC}: the delegation role {ROLE} does not allow it", errors[0])


if __name__ == "__main__":
    unittest.main()
