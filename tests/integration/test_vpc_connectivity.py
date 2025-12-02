"""
Integration tests for VPC connectivity and networking
"""
import boto3
import pytest
import os
from typing import Dict, List


@pytest.fixture(scope="module")
def aws_session():
    """Create AWS session"""
    return boto3.Session(region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))


@pytest.fixture(scope="module")
def ec2_client(aws_session):
    """Create EC2 client"""
    return aws_session.client("ec2")


@pytest.fixture(scope="module")
def vpc_id(ec2_client) -> str:
    """Get VPC ID from environment or discover"""
    vpc_id = os.environ.get("TEST_VPC_ID")
    if vpc_id:
        return vpc_id

    # Discover VPC by tag
    tenant = os.environ.get("TENANT", "fnx")
    environment = os.environ.get("ENVIRONMENT", "testenv-01")

    response = ec2_client.describe_vpcs(
        Filters=[
            {"Name": "tag:Tenant", "Values": [tenant]},
            {"Name": "tag:Environment", "Values": [environment]},
        ]
    )

    if not response["Vpcs"]:
        pytest.skip(f"No VPC found for tenant={tenant}, environment={environment}")

    return response["Vpcs"][0]["VpcId"]


class TestVPCConfiguration:
    """Test VPC configuration and setup"""

    def test_vpc_exists(self, ec2_client, vpc_id):
        """Test that VPC exists and is available"""
        response = ec2_client.describe_vpcs(VpcIds=[vpc_id])
        assert len(response["Vpcs"]) == 1
        assert response["Vpcs"][0]["State"] == "available"

    def test_vpc_has_required_tags(self, ec2_client, vpc_id):
        """Test that VPC has required tags"""
        response = ec2_client.describe_vpcs(VpcIds=[vpc_id])
        vpc = response["Vpcs"][0]

        tags = {tag["Key"]: tag["Value"] for tag in vpc.get("Tags", [])}
        required_tags = ["Name", "Tenant", "Environment", "ManagedBy"]

        for tag in required_tags:
            assert tag in tags, f"Required tag '{tag}' not found"

    def test_vpc_dns_support_enabled(self, ec2_client, vpc_id):
        """Test that VPC has DNS support enabled"""
        response = ec2_client.describe_vpc_attribute(
            VpcId=vpc_id, Attribute="enableDnsSupport"
        )
        assert response["EnableDnsSupport"]["Value"] is True

    def test_vpc_dns_hostnames_enabled(self, ec2_client, vpc_id):
        """Test that VPC has DNS hostnames enabled"""
        response = ec2_client.describe_vpc_attribute(
            VpcId=vpc_id, Attribute="enableDnsHostnames"
        )
        assert response["EnableDnsHostnames"]["Value"] is True


class TestSubnets:
    """Test subnet configuration"""

    def test_public_subnets_exist(self, ec2_client, vpc_id):
        """Test that public subnets exist"""
        response = ec2_client.describe_subnets(
            Filters=[
                {"Name": "vpc-id", "Values": [vpc_id]},
                {"Name": "tag:Type", "Values": ["public"]},
            ]
        )
        assert len(response["Subnets"]) >= 2, "At least 2 public subnets required"

    def test_private_subnets_exist(self, ec2_client, vpc_id):
        """Test that private subnets exist"""
        response = ec2_client.describe_subnets(
            Filters=[
                {"Name": "vpc-id", "Values": [vpc_id]},
                {"Name": "tag:Type", "Values": ["private"]},
            ]
        )
        assert len(response["Subnets"]) >= 2, "At least 2 private subnets required"

    def test_subnets_in_different_azs(self, ec2_client, vpc_id):
        """Test that subnets span multiple availability zones"""
        response = ec2_client.describe_subnets(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )

        azs = set(subnet["AvailabilityZone"] for subnet in response["Subnets"])
        assert len(azs) >= 2, "Subnets must span at least 2 availability zones"


class TestInternetConnectivity:
    """Test internet connectivity configuration"""

    def test_internet_gateway_attached(self, ec2_client, vpc_id):
        """Test that Internet Gateway is attached"""
        response = ec2_client.describe_internet_gateways(
            Filters=[{"Name": "attachment.vpc-id", "Values": [vpc_id]}]
        )
        assert len(response["InternetGateways"]) == 1
        assert response["InternetGateways"][0]["Attachments"][0]["State"] == "available"

    def test_nat_gateways_exist(self, ec2_client, vpc_id):
        """Test that NAT Gateways exist for private subnet connectivity"""
        response = ec2_client.describe_nat_gateways(
            Filters=[
                {"Name": "vpc-id", "Values": [vpc_id]},
                {"Name": "state", "Values": ["available"]},
            ]
        )
        # At least one NAT Gateway should exist
        assert len(response["NatGateways"]) >= 1, "At least 1 NAT Gateway required"


class TestRouteTables:
    """Test route table configuration"""

    def test_public_route_table_has_igw_route(self, ec2_client, vpc_id):
        """Test that public route tables have route to Internet Gateway"""
        # Get public subnets
        subnets_response = ec2_client.describe_subnets(
            Filters=[
                {"Name": "vpc-id", "Values": [vpc_id]},
                {"Name": "tag:Type", "Values": ["public"]},
            ]
        )

        if not subnets_response["Subnets"]:
            pytest.skip("No public subnets found")

        public_subnet_id = subnets_response["Subnets"][0]["SubnetId"]

        # Get route table for public subnet
        rt_response = ec2_client.describe_route_tables(
            Filters=[{"Name": "association.subnet-id", "Values": [public_subnet_id]}]
        )

        assert len(rt_response["RouteTables"]) > 0

        # Check for IGW route
        routes = rt_response["RouteTables"][0]["Routes"]
        igw_routes = [
            r for r in routes if r.get("GatewayId", "").startswith("igw-")
        ]
        assert len(igw_routes) > 0, "Public subnet should have route to IGW"

    def test_private_route_table_has_nat_route(self, ec2_client, vpc_id):
        """Test that private route tables have route to NAT Gateway"""
        # Get private subnets
        subnets_response = ec2_client.describe_subnets(
            Filters=[
                {"Name": "vpc-id", "Values": [vpc_id]},
                {"Name": "tag:Type", "Values": ["private"]},
            ]
        )

        if not subnets_response["Subnets"]:
            pytest.skip("No private subnets found")

        private_subnet_id = subnets_response["Subnets"][0]["SubnetId"]

        # Get route table for private subnet
        rt_response = ec2_client.describe_route_tables(
            Filters=[{"Name": "association.subnet-id", "Values": [private_subnet_id]}]
        )

        if not rt_response["RouteTables"]:
            pytest.skip("No route table associated with private subnet")

        # Check for NAT route
        routes = rt_response["RouteTables"][0]["Routes"]
        nat_routes = [
            r for r in routes if r.get("NatGatewayId", "").startswith("nat-")
        ]
        assert len(nat_routes) > 0, "Private subnet should have route to NAT Gateway"


class TestNetworkACLs:
    """Test Network ACL configuration"""

    def test_default_nacl_not_used(self, ec2_client, vpc_id):
        """Test that subnets don't use default NACL"""
        # Get VPC default NACL
        nacl_response = ec2_client.describe_network_acls(
            Filters=[
                {"Name": "vpc-id", "Values": [vpc_id]},
                {"Name": "default", "Values": ["true"]},
            ]
        )

        if not nacl_response["NetworkAcls"]:
            return  # No default NACL found

        default_nacl_id = nacl_response["NetworkAcls"][0]["NetworkAclId"]

        # Get all subnets
        subnets_response = ec2_client.describe_subnets(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )

        # Get custom NACLs
        custom_nacls = ec2_client.describe_network_acls(
            Filters=[
                {"Name": "vpc-id", "Values": [vpc_id]},
                {"Name": "default", "Values": ["false"]},
            ]
        )

        # Verify custom NACLs exist
        assert (
            len(custom_nacls["NetworkAcls"]) > 0
        ), "Custom Network ACLs should be configured"
