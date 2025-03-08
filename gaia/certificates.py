#!/usr/bin/env python3
"""
Certificate management module for Gaia.
Handles certificate operations including rotation and synchronization with Kubernetes.
"""

import os
import sys
import json
import subprocess
import tempfile
import shutil
import logging
import datetime
import time
import re
import base64
from dataclasses import dataclass
from typing import Optional, Dict, List, Any, Tuple, Union
import boto3
from botocore.exceptions import ClientError
from botocore.config import Config

from .logger import setup_logger
from .config import get_config

# Set up logger
logger = setup_logger()

@dataclass
class CertificateDetails:
    """Details of a certificate."""
    domain_name: str
    status: str
    cert_type: str
    expiry_date: Optional[str] = None
    acm_arn: Optional[str] = None
    certificate: Optional[str] = None
    certificate_chain: Optional[str] = None


class CertificateManager:
    """Manager for certificate operations."""

    def __init__(
        self, 
        region: Optional[str] = None, 
        profile: Optional[str] = None,
        retry_attempts: int = 5,
        debug: bool = False
    ):
        """
        Initialize the certificate manager.
        
        Args:
            region: AWS region
            profile: AWS profile name
            retry_attempts: Number of retry attempts for AWS operations
            debug: Enable debug logging
        """
        self.region = region or self._get_default_region()
        self.profile = profile
        self.retry_attempts = retry_attempts
        
        # Set up logging
        if debug:
            logging.getLogger().setLevel(logging.DEBUG)
        
        # Configure boto3 retry settings
        self.boto_config = Config(
            retries=dict(
                max_attempts=retry_attempts,
                mode='adaptive'
            )
        )
        
        # Initialize AWS session
        self.session = boto3.Session(
            region_name=self.region,
            profile_name=self.profile
        )
        
        # Initialize AWS clients
        self.acm_client = self.session.client('acm', config=self.boto_config)
        self.sm_client = self.session.client('secretsmanager', config=self.boto_config)

    def _get_default_region(self) -> str:
        """Get the default AWS region from environment or config."""
        # Check environment first
        if 'AWS_REGION' in os.environ:
            return os.environ['AWS_REGION']
        
        # Then try AWS_DEFAULT_REGION
        if 'AWS_DEFAULT_REGION' in os.environ:
            return os.environ['AWS_DEFAULT_REGION']
        
        # Try boto3 session default
        try:
            session = boto3.Session()
            return session.region_name or 'us-east-1'
        except Exception:
            # Fall back to us-east-1 if all else fails
            return 'us-east-1'

    def check_secret_exists(self, secret_name: str) -> bool:
        """
        Check if a secret exists in AWS Secrets Manager.
        
        Args:
            secret_name: Name of the secret
            
        Returns:
            True if the secret exists, False otherwise
        """
        try:
            self.sm_client.describe_secret(SecretId=secret_name)
            return True
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                return False
            # For any other error, log and re-raise
            logger.error(f"Error checking if secret exists: {e}")
            raise

    def get_certificate_details(self, cert_arn: str) -> CertificateDetails:
        """
        Get certificate details from AWS ACM.
        
        Args:
            cert_arn: ACM certificate ARN
            
        Returns:
            CertificateDetails object with certificate information
        """
        try:
            response = self.acm_client.describe_certificate(CertificateArn=cert_arn)
            cert = response['Certificate']
            
            # Extract key details
            domain_name = cert.get('DomainName', '')
            status = cert.get('Status', '')
            cert_type = cert.get('Type', 'IMPORTED')
            
            # Handle expiry date
            expiry_date = None
            if 'NotAfter' in cert:
                notafter = cert['NotAfter']
                if isinstance(notafter, datetime.datetime):
                    expiry_date = notafter.strftime('%Y-%m-%d %H:%M:%S')
                    
            return CertificateDetails(
                domain_name=domain_name,
                status=status,
                cert_type=cert_type,
                expiry_date=expiry_date,
                acm_arn=cert_arn
            )
        except ClientError as e:
            logger.error(f"Error getting certificate details: {e}")
            raise

    def get_certificate_content(self, cert_arn: str) -> Tuple[str, str]:
        """
        Get certificate content from AWS ACM.
        
        Args:
            cert_arn: ACM certificate ARN
            
        Returns:
            Tuple of (certificate, certificate_chain)
        """
        try:
            response = self.acm_client.get_certificate(CertificateArn=cert_arn)
            certificate = response.get('Certificate', '')
            certificate_chain = response.get('CertificateChain', '')
            
            # Check if certificate appears to be base64-encoded
            if re.match(r'^[A-Za-z0-9+/]+={0,2}$', certificate) and "BEGIN CERTIFICATE" not in certificate:
                try:
                    certificate = base64.b64decode(certificate).decode('utf-8')
                    if certificate_chain and re.match(r'^[A-Za-z0-9+/]+={0,2}$', certificate_chain):
                        certificate_chain = base64.b64decode(certificate_chain).decode('utf-8')
                except Exception as e:
                    logger.warning(f"Failed to decode base64 certificate: {e}")
            
            return certificate, certificate_chain
        except ClientError as e:
            logger.error(f"Error getting certificate content: {e}")
            raise

    def get_secret_value(self, secret_name: str) -> Dict[str, Any]:
        """
        Get secret value from AWS Secrets Manager.
        
        Args:
            secret_name: Name of the secret
            
        Returns:
            Dictionary of secret key-value pairs
        """
        try:
            response = self.sm_client.get_secret_value(SecretId=secret_name)
            secret_string = response.get('SecretString', '{}')
            return json.loads(secret_string)
        except ClientError as e:
            logger.error(f"Error getting secret value: {e}")
            raise
        except json.JSONDecodeError as e:
            logger.error(f"Error parsing secret value as JSON: {e}")
            raise

    def update_secret(self, secret_name: str, secret_data: Dict[str, Any]) -> bool:
        """
        Update a secret in AWS Secrets Manager.
        
        Args:
            secret_name: Name of the secret
            secret_data: Dictionary of secret key-value pairs
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Convert dictionary to JSON string
            secret_string = json.dumps(secret_data)
            
            # Update the secret
            response = self.sm_client.update_secret(
                SecretId=secret_name,
                SecretString=secret_string
            )
            
            # Verify the update
            description = self.sm_client.describe_secret(SecretId=secret_name)
            last_changed = description.get('LastChangedDate')
            
            # Check if the update was recent (within last 60 seconds)
            if last_changed:
                if isinstance(last_changed, datetime.datetime):
                    last_changed_epoch = int(last_changed.timestamp())
                    now_epoch = int(time.time())
                    if now_epoch - last_changed_epoch > 60:
                        logger.warning("Secret update may not have been applied. LastChangedDate is not recent.")
                        return False
            
            return True
        except ClientError as e:
            logger.error(f"Error updating secret: {e}")
            raise

    def _validate_certificate_chain(self, cert_path: str, chain_path: str) -> bool:
        """
        Validate a certificate chain.
        
        Args:
            cert_path: Path to certificate file
            chain_path: Path to certificate chain file
            
        Returns:
            True if valid, False otherwise
        """
        try:
            result = subprocess.run(
                ['openssl', 'verify', '-untrusted', chain_path, cert_path],
                check=False,
                capture_output=True,
                text=True
            )
            return result.returncode == 0
        except Exception as e:
            logger.error(f"Error validating certificate chain: {e}")
            return False

    def _fix_certificate_chain(self, cert_path: str, chain_path: str, output_path: str) -> bool:
        """
        Attempt to fix certificate chain order.
        
        Args:
            cert_path: Path to certificate file
            chain_path: Path to certificate chain file
            output_path: Path to output fixed chain file
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Read the chain file content
            with open(chain_path, 'r') as f:
                chain_content = f.read()
            
            # Split into individual certificates
            certs = re.split(r'(?=-----BEGIN CERTIFICATE-----)', chain_content)
            certs = [cert for cert in certs if cert.strip()]
            
            # Combine leaf certificate with chain certs
            with open(cert_path, 'r') as f:
                leaf_cert = f.read()
            
            with open(output_path, 'w') as f:
                f.write(leaf_cert)
                for cert in certs:
                    f.write(cert)
            
            return True
        except Exception as e:
            logger.error(f"Error fixing certificate chain: {e}")
            return False

    def rotate_certificate(
        self,
        secret_name: str,
        namespace: str,
        acm_cert_arn: Optional[str] = None,
        private_key_path: Optional[str] = None,
        k8s_secret: Optional[str] = None,
        kube_context: Optional[str] = None,
        auto_restart_pods: bool = False
    ) -> bool:
        """
        Rotate a certificate in AWS Secrets Manager and update Kubernetes.
        
        Args:
            secret_name: AWS Secret name in Secrets Manager
            namespace: Kubernetes namespace
            acm_cert_arn: ACM certificate ARN (optional)
            private_key_path: Path to private key file (optional)
            k8s_secret: Kubernetes secret name (optional, defaults to secret_name basename)
            kube_context: Kubernetes context (optional)
            auto_restart_pods: Whether to automatically restart pods using the secret
            
        Returns:
            True if successful, False otherwise
        """
        # Set default k8s_secret if not provided
        if not k8s_secret:
            k8s_secret = os.path.basename(secret_name)
        
        # Log parameters
        logger.info("Starting certificate rotation process...")
        logger.info(f"AWS Secret: {secret_name}")
        logger.info(f"Region: {self.region}")
        logger.info(f"Kubernetes Namespace: {namespace}")
        logger.info(f"Kubernetes Secret: {k8s_secret}")
        
        # Check if AWS secret exists
        logger.info("Checking if secret exists in AWS Secrets Manager...")
        if not self.check_secret_exists(secret_name):
            logger.error(f"Secret {secret_name} not found in AWS Secrets Manager")
            return False
        
        # Create temporary directory with secure permissions
        with tempfile.TemporaryDirectory() as temp_dir:
            # Set secure permissions (equivalent to chmod 700)
            os.chmod(temp_dir, 0o700)
            
            # If a new ACM ARN is provided, update the certificate
            if acm_cert_arn:
                logger.info(f"New ACM certificate ARN provided: {acm_cert_arn}")
                
                # Get certificate details
                logger.info("Fetching certificate details from ACM...")
                cert_details = self.get_certificate_details(acm_cert_arn)
                
                # Check certificate status
                if cert_details.status != 'ISSUED':
                    logger.error(f"Certificate is not in ISSUED state. Current status: {cert_details.status}")
                    return False
                
                # Log certificate details
                logger.info(f"Domain: {cert_details.domain_name}")
                logger.info(f"Status: {cert_details.status}")
                logger.info(f"Type: {cert_details.cert_type}")
                logger.info(f"Expires: {cert_details.expiry_date or 'Unknown'}")
                
                # Get certificate content
                logger.info("Getting certificate content from ACM...")
                certificate, certificate_chain = self.get_certificate_content(acm_cert_arn)
                
                if not certificate:
                    logger.error("Failed to extract certificate from ACM response")
                    return False
                
                # Save certificate to files
                cert_path = os.path.join(temp_dir, 'tls.crt')
                chain_path = os.path.join(temp_dir, 'chain.crt')
                fullchain_path = os.path.join(temp_dir, 'fullchain.crt')
                
                with open(cert_path, 'w') as f:
                    f.write(certificate)
                
                with open(chain_path, 'w') as f:
                    f.write(certificate_chain)
                
                # Validate certificate chain
                if "BEGIN CERTIFICATE" in certificate_chain:
                    if not self._validate_certificate_chain(cert_path, chain_path):
                        logger.warning("Certificate chain validation failed. Attempting to fix chain order...")
                        if not self._fix_certificate_chain(cert_path, chain_path, fullchain_path):
                            logger.error("Failed to fix certificate chain")
                            return False
                    else:
                        # Chain is valid, create fullchain in proper order
                        with open(fullchain_path, 'w') as f:
                            f.write(certificate)
                            f.write(certificate_chain)
                else:
                    # No chain certificates, just use the leaf certificate
                    shutil.copy(cert_path, fullchain_path)
                
                # Handle private key
                key_path = os.path.join(temp_dir, 'tls.key')
                
                if cert_details.cert_type != 'IMPORTED':
                    logger.info("This is an AWS-managed certificate. Private key is not available from ACM.")
                    if not private_key_path:
                        logger.error("Private key path must be provided for AWS-managed certificates")
                        return False
                    
                    if not os.path.isfile(private_key_path):
                        logger.error(f"Private key file not found at {private_key_path}")
                        return False
                    
                    # Copy the private key
                    shutil.copy(private_key_path, key_path)
                else:
                    logger.info("This is an imported certificate. You may need to provide the original private key.")
                    
                    if private_key_path:
                        logger.info(f"Using provided private key from: {private_key_path}")
                        
                        if not os.path.isfile(private_key_path):
                            logger.error(f"Private key file not found at {private_key_path}")
                            return False
                        
                        # Copy the private key
                        shutil.copy(private_key_path, key_path)
                    else:
                        logger.info("Using existing private key from the secret...")
                        
                        # Get existing secret
                        try:
                            secret_value = self.get_secret_value(secret_name)
                            private_key = secret_value.get('tls.key', '')
                            
                            if not private_key:
                                logger.error("Could not extract private key from existing secret")
                                return False
                            
                            with open(key_path, 'w') as f:
                                f.write(private_key)
                        except Exception as e:
                            logger.error(f"Error extracting private key from existing secret: {e}")
                            return False
                
                # Create JSON for the updated secret
                with open(cert_path, 'r') as f:
                    cert_content = f.read()
                
                with open(key_path, 'r') as f:
                    key_content = f.read()
                
                secret_data = {
                    'tls.crt': certificate,
                    'tls.key': key_content,
                    'domain': cert_details.domain_name,
                    'expiry': cert_details.expiry_date or '',
                    'acm_arn': acm_cert_arn,
                    'updated_at': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
                }
                
                # Update the secret in AWS Secrets Manager
                logger.info(f"Updating secret in AWS Secrets Manager: {secret_name}")
                try:
                    if not self.update_secret(secret_name, secret_data):
                        logger.error("Failed to update secret in AWS Secrets Manager")
                        return False
                    logger.info("Secret successfully updated in AWS Secrets Manager")
                except Exception as e:
                    logger.error(f"Error updating secret: {e}")
                    return False
            
            # Check if ExternalSecret exists in Kubernetes
            logger.info("Checking for ExternalSecret in Kubernetes...")
            
            # Build kubectl command for checking ExternalSecret
            cmd = ['kubectl', 'get', 'externalsecret', '-n', namespace]
            if kube_context:
                cmd.extend(['--context', kube_context])
            
            try:
                result = subprocess.run(
                    cmd,
                    check=False,
                    capture_output=True,
                    text=True
                )
                
                # Process the output to check if the secret exists
                external_secret_exists = k8s_secret in result.stdout
                
                if not external_secret_exists:
                    logger.info("ExternalSecret not found. Creating it now...")
                    
                    # Create the ExternalSecret YAML
                    external_secret_yaml = f"""apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {k8s_secret}
  namespace: {namespace}
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: aws-certificate-store
    kind: ClusterSecretStore
  target:
    name: {k8s_secret}
    creationPolicy: Owner
    template:
      type: kubernetes.io/tls
  data:
  - secretKey: tls.crt
    remoteRef:
      key: "{secret_name}"
      property: tls.crt
  - secretKey: tls.key
    remoteRef:
      key: "{secret_name}"
      property: tls.key
"""
                    
                    # Save YAML to a temporary file
                    yaml_path = os.path.join(temp_dir, 'external-secret.yaml')
                    with open(yaml_path, 'w') as f:
                        f.write(external_secret_yaml)
                    
                    # Apply the YAML
                    apply_cmd = ['kubectl', 'apply', '-f', yaml_path]
                    if kube_context:
                        apply_cmd.extend(['--context', kube_context])
                    
                    result = subprocess.run(apply_cmd, check=False, capture_output=True, text=True)
                    
                    if result.returncode != 0:
                        logger.error(f"Failed to create ExternalSecret: {result.stderr}")
                        return False
                    
                    logger.info("ExternalSecret created")
                else:
                    logger.info("ExternalSecret already exists. Triggering a refresh...")
                    
                    # Check if ExternalSecret actually exists before annotating
                    check_cmd = ['kubectl', 'get', 'externalsecret', k8s_secret, '-n', namespace]
                    if kube_context:
                        check_cmd.extend(['--context', kube_context])
                    
                    result = subprocess.run(check_cmd, check=False, capture_output=True, text=True)
                    
                    if result.returncode == 0:
                        # Add annotation to force refresh
                        timestamp = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
                        annotate_cmd = [
                            'kubectl', 'annotate', 'externalsecret', k8s_secret, 
                            '-n', namespace, f'externalsecrets.io/force-sync="{timestamp}"', '--overwrite'
                        ]
                        if kube_context:
                            annotate_cmd.extend(['--context', kube_context])
                        
                        result = subprocess.run(annotate_cmd, check=False, capture_output=True, text=True)
                        
                        if result.returncode != 0:
                            logger.error(f"Failed to annotate ExternalSecret: {result.stderr}")
                            return False
                        
                        logger.info("ExternalSecret refresh triggered")
                    else:
                        logger.warning("ExternalSecret exists but couldn't be accessed. Refresh not triggered.")
                        logger.warning("This could be due to permission issues or a namespace mismatch.")
                
                # Wait for the secret refresh to complete
                logger.info("Waiting for secret refresh to complete...")
                timeout = 60
                interval = 2
                elapsed = 0
                
                while elapsed < timeout:
                    # Check if the secret exists and verify it has been updated
                    secret_cmd = ['kubectl', 'get', 'secret', k8s_secret, '-n', namespace]
                    if kube_context:
                        secret_cmd.extend(['--context', kube_context])
                    
                    result = subprocess.run(secret_cmd, check=False, capture_output=True, text=True)
                    
                    if result.returncode == 0:
                        # Get the last update time of the secret
                        timestamp_cmd = [
                            'kubectl', 'get', 'secret', k8s_secret, '-n', namespace, 
                            '-o', 'jsonpath={.metadata.creationTimestamp}'
                        ]
                        if kube_context:
                            timestamp_cmd.extend(['--context', kube_context])
                        
                        result = subprocess.run(timestamp_cmd, check=False, capture_output=True, text=True)
                        
                        if result.returncode == 0:
                            secret_update_time = result.stdout.strip()
                            
                            # Convert to epoch for comparison
                            try:
                                # Parse ISO format timestamp
                                update_time = datetime.datetime.strptime(
                                    secret_update_time, '%Y-%m-%dT%H:%M:%SZ'
                                ).replace(tzinfo=datetime.timezone.utc)
                                secret_update_epoch = int(update_time.timestamp())
                                
                                # Get current time
                                current_epoch = int(time.time())
                                
                                # If the secret was updated within the last two minutes, consider it done
                                if current_epoch - secret_update_epoch < 120:
                                    logger.info("Secret was successfully refreshed")
                                    break
                            except Exception as e:
                                logger.error(f"Error parsing secret timestamp: {e}")
                    
                    # Sleep and increment counter
                    time.sleep(interval)
                    elapsed += interval
                    sys.stdout.write(".")
                    sys.stdout.flush()
                
                if elapsed >= timeout:
                    logger.warning("Timed out waiting for secret refresh. The ExternalSecret may still be processing.")
                
                # Check if Kubernetes secret exists and is up-to-date
                logger.info("Checking Kubernetes secret status...")
                secret_cmd = ['kubectl', 'get', 'secret', k8s_secret, '-n', namespace]
                if kube_context:
                    secret_cmd.extend(['--context', kube_context])
                
                result = subprocess.run(secret_cmd, check=False, capture_output=True, text=True)
                
                if result.returncode != 0:
                    logger.warning("Kubernetes secret doesn't exist yet. It may take a moment to be created.")
                else:
                    age_cmd = [
                        'kubectl', 'get', 'secret', k8s_secret, '-n', namespace, 
                        '-o', 'jsonpath={.metadata.creationTimestamp}'
                    ]
                    if kube_context:
                        age_cmd.extend(['--context', kube_context])
                    
                    result = subprocess.run(age_cmd, check=False, capture_output=True, text=True)
                    secret_age = result.stdout.strip()
                    
                    logger.info(f"Kubernetes secret exists (created at {secret_age})")
                
                # Check for pods that mount this secret
                logger.info("Checking for pods that mount this secret...")
                pods_cmd = [
                    'kubectl', 'get', 'pods', '-n', namespace, '-o', 'json'
                ]
                if kube_context:
                    pods_cmd.extend(['--context', kube_context])
                
                result = subprocess.run(pods_cmd, check=False, capture_output=True, text=True)
                
                if result.returncode == 0:
                    # Parse JSON output
                    try:
                        pods_data = json.loads(result.stdout)
                        pods_with_secret = []
                        
                        # Find pods that mount the secret
                        for pod in pods_data.get('items', []):
                            volumes = pod.get('spec', {}).get('volumes', [])
                            for volume in volumes:
                                if 'secret' in volume and volume['secret'].get('secretName') == k8s_secret:
                                    pods_with_secret.append(pod['metadata']['name'])
                                    break
                        
                        if pods_with_secret:
                            logger.info("The following pods mount this secret and may need a restart:")
                            for pod in pods_with_secret:
                                logger.info(f"  - {pod}")
                            
                            # Handle pod restart
                            if auto_restart_pods:
                                logger.info("Auto-restarting pods is enabled.")
                                
                                for pod in pods_with_secret:
                                    logger.info(f"Restarting pod: {pod}")
                                    restart_cmd = ['kubectl', 'delete', 'pod', pod, '-n', namespace]
                                    if kube_context:
                                        restart_cmd.extend(['--context', kube_context])
                                    
                                    result = subprocess.run(restart_cmd, check=False, capture_output=True, text=True)
                                    
                                    if result.returncode != 0:
                                        logger.error(f"Failed to restart pod {pod}: {result.stderr}")
                                
                                logger.info("Pods restarted")
                            else:
                                logger.info("Pods were not restarted. You may need to restart them manually.")
                        else:
                            logger.info("No pods found that directly mount this secret.")
                    except json.JSONDecodeError as e:
                        logger.error(f"Error parsing pod data: {e}")
            except Exception as e:
                logger.error(f"Error working with Kubernetes resources: {e}")
                return False
            
            logger.info("Certificate rotation process completed successfully!")
            return True


def rotate_certificate(
    secret_name: str,
    namespace: str,
    acm_cert_arn: Optional[str] = None,
    region: Optional[str] = None,
    kube_context: Optional[str] = None,
    k8s_secret: Optional[str] = None,
    profile: Optional[str] = None,
    private_key_path: Optional[str] = None,
    auto_restart_pods: bool = False,
    debug: bool = False
) -> Dict[str, Any]:
    """
    Rotate a certificate in AWS Secrets Manager and update Kubernetes.
    
    Args:
        secret_name: AWS Secret name in Secrets Manager
        namespace: Kubernetes namespace
        acm_cert_arn: ACM certificate ARN (optional)
        region: AWS region (optional)
        kube_context: Kubernetes context (optional)
        k8s_secret: Kubernetes secret name (optional)
        profile: AWS profile (optional)
        private_key_path: Path to private key file (optional)
        auto_restart_pods: Whether to automatically restart pods using the secret
        debug: Enable debug logging
        
    Returns:
        Dictionary with operation results
    """
    try:
        # Initialize certificate manager
        cert_manager = CertificateManager(
            region=region,
            profile=profile,
            debug=debug
        )
        
        # Perform certificate rotation
        success = cert_manager.rotate_certificate(
            secret_name=secret_name,
            namespace=namespace,
            acm_cert_arn=acm_cert_arn,
            private_key_path=private_key_path,
            k8s_secret=k8s_secret,
            kube_context=kube_context,
            auto_restart_pods=auto_restart_pods
        )
        
        if success:
            return {
                "success": True,
                "message": f"Certificate rotation completed for {secret_name} in namespace {namespace}",
                "secret_name": secret_name,
                "namespace": namespace,
                "k8s_secret": k8s_secret or os.path.basename(secret_name)
            }
        else:
            return {
                "success": False,
                "error": "Certificate rotation failed. See logs for details.",
                "secret_name": secret_name,
                "namespace": namespace
            }
    except Exception as e:
        logger.error(f"Error during certificate rotation: {e}")
        return {
            "success": False,
            "error": str(e),
            "secret_name": secret_name,
            "namespace": namespace
        }