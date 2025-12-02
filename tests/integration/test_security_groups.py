"""
Integration tests for security groups
"""
import boto3
import pytest
import os


@pytest.fixture(scope="module")
def ec2_client():
    """Create EC2 client"""
    return boto3.client("ec2", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))


@pytest.fixture(scope="module")
def vpc_id(ec2_client) -> str:
    """Get VPC ID"""
    vpc_id = os.environ.get("TEST_VPC_ID")
    if vpc_id:
        return vpc_id

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


class TestSecurityGroups:
    """Test security group configuration"""

    def test_no_security_group_allows_all_traffic(self, ec2_client, vpc_id):
        """Test that no security group allows unrestricted access (0.0.0.0/0) on all ports"""
        response = ec2_client.describe_security_groups(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )

        violations = []
        for sg in response["SecurityGroups"]:
            for permission in sg.get("IpPermissions", []):
                # Check for unrestricted access
                for ip_range in permission.get("IpRanges", []):
                    if ip_range.get("CidrIp") == "0.0.0.0/0":
                        # Allow only specific ports (80, 443) from 0.0.0.0/0
                        from_port = permission.get("FromPort", -1)
                        to_port = permission.get("ToPort", -1)

                        if from_port == -1 or (from_port < 80 and to_port > 443):
                            violations.append(
                                f"SG {sg['GroupId']} ({sg['GroupName']}) allows unrestricted access on ports {from_port}-{to_port}"
                            )

        assert not violations, f"Security violations found: {violations}"

    def test_security_groups_have_descriptions(self, ec2_client, vpc_id):
        """Test that all security groups have descriptions"""
        response = ec2_client.describe_security_groups(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )

        for sg in response["SecurityGroups"]:
            # Skip default security group
            if sg["GroupName"] == "default":
                continue

            assert sg["Description"], f"Security group {sg['GroupId']} has no description"
            assert (
                sg["Description"] != "Managed by Terraform"
            ), f"Security group {sg['GroupId']} has generic description"

    def test_security_groups_have_tags(self, ec2_client, vpc_id):
        """Test that all security groups have required tags"""
        response = ec2_client.describe_security_groups(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )

        required_tags = ["Name", "Environment"]

        for sg in response["SecurityGroups"]:
            # Skip default security group
            if sg["GroupName"] == "default":
                continue

            tags = {tag["Key"]: tag["Value"] for tag in sg.get("Tags", [])}

            for tag in required_tags:
                assert tag in tags, f"Security group {sg['GroupId']} missing tag: {tag}"

    def test_no_security_group_allows_rdp_from_internet(self, ec2_client, vpc_id):
        """Test that RDP (port 3389) is not open to the internet"""
        response = ec2_client.describe_security_groups(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )

        violations = []
        for sg in response["SecurityGroups"]:
            for permission in sg.get("IpPermissions", []):
                from_port = permission.get("FromPort")
                to_port = permission.get("ToPort")

                # Check if RDP port is allowed
                if from_port == 3389 or (
                    from_port and to_port and from_port <= 3389 <= to_port
                ):
                    for ip_range in permission.get("IpRanges", []):
                        if ip_range.get("CidrIp") == "0.0.0.0/0":
                            violations.append(
                                f"SG {sg['GroupId']} ({sg['GroupName']}) allows RDP from internet"
                            )

        assert not violations, f"RDP security violations found: {violations}"

    def test_no_security_group_allows_ssh_from_internet(self, ec2_client, vpc_id):
        """Test that SSH (port 22) is not open to the internet (except bastion)"""
        response = ec2_client.describe_security_groups(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )

        violations = []
        for sg in response["SecurityGroups"]:
            # Allow bastion security groups
            if "bastion" in sg["GroupName"].lower():
                continue

            for permission in sg.get("IpPermissions", []):
                from_port = permission.get("FromPort")
                to_port = permission.get("ToPort")

                # Check if SSH port is allowed
                if from_port == 22 or (
                    from_port and to_port and from_port <= 22 <= to_port
                ):
                    for ip_range in permission.get("IpRanges", []):
                        if ip_range.get("CidrIp") == "0.0.0.0/0":
                            violations.append(
                                f"SG {sg['GroupId']} ({sg['GroupName']}) allows SSH from internet"
                            )

        assert not violations, f"SSH security violations found: {violations}"
