#!/usr/bin/env python3
"""
IDP Cost Optimization Report Generator
Analyzes AWS costs and provides optimization recommendations
"""

import boto3
import json
import pandas as pd
from datetime import datetime, timedelta
from typing import Dict, List, Any
import argparse
import sys

class CostOptimizer:
    def __init__(self, profile: str = None, region: str = 'us-east-1'):
        """Initialize AWS clients"""
        session = boto3.Session(profile_name=profile) if profile else boto3.Session()
        self.ce = session.client('ce', region_name=region)
        self.ec2 = session.client('ec2', region_name=region)
        self.rds = session.client('rds', region_name=region)
        self.cloudwatch = session.client('cloudwatch', region_name=region)
        self.compute_optimizer = session.client('compute-optimizer', region_name=region)
        
    def get_monthly_costs(self, months: int = 6) -> pd.DataFrame:
        """Get monthly cost breakdown for the last N months"""
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=months * 30)
        
        response = self.ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['UnblendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'TAG', 'Key': 'Environment'}
            ]
        )
        
        costs = []
        for result in response['ResultsByTime']:
            period = result['TimePeriod']['Start']
            for group in result['Groups']:
                service = group['Keys'][0]
                environment = group['Keys'][1] if len(group['Keys']) > 1 else 'Untagged'
                amount = float(group['Metrics']['UnblendedCost']['Amount'])
                costs.append({
                    'Month': period,
                    'Service': service,
                    'Environment': environment,
                    'Cost': amount
                })
        
        return pd.DataFrame(costs)
    
    def get_underutilized_resources(self) -> Dict[str, List[Dict]]:
        """Identify underutilized EC2 and RDS instances"""
        recommendations = {
            'ec2_rightsizing': [],
            'rds_rightsizing': [],
            'unused_volumes': [],
            'old_snapshots': []
        }
        
        # Check EC2 instances
        instances = self.ec2.describe_instances()
        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                if instance['State']['Name'] == 'running':
                    instance_id = instance['InstanceId']
                    
                    # Get CPU utilization
                    cpu_stats = self.cloudwatch.get_metric_statistics(
                        Namespace='AWS/EC2',
                        MetricName='CPUUtilization',
                        Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
                        StartTime=datetime.now() - timedelta(days=7),
                        EndTime=datetime.now(),
                        Period=3600,
                        Statistics=['Average']
                    )
                    
                    if cpu_stats['Datapoints']:
                        avg_cpu = sum(d['Average'] for d in cpu_stats['Datapoints']) / len(cpu_stats['Datapoints'])
                        if avg_cpu < 20:
                            recommendations['ec2_rightsizing'].append({
                                'instance_id': instance_id,
                                'instance_type': instance['InstanceType'],
                                'avg_cpu': round(avg_cpu, 2),
                                'recommendation': 'Downsize or terminate'
                            })
        
        # Check RDS instances
        db_instances = self.rds.describe_db_instances()
        for db in db_instances['DBInstances']:
            db_id = db['DBInstanceIdentifier']
            
            # Get CPU utilization
            cpu_stats = self.cloudwatch.get_metric_statistics(
                Namespace='AWS/RDS',
                MetricName='CPUUtilization',
                Dimensions=[{'Name': 'DBInstanceIdentifier', 'Value': db_id}],
                StartTime=datetime.now() - timedelta(days=7),
                EndTime=datetime.now(),
                Period=3600,
                Statistics=['Average']
            )
            
            if cpu_stats['Datapoints']:
                avg_cpu = sum(d['Average'] for d in cpu_stats['Datapoints']) / len(cpu_stats['Datapoints'])
                if avg_cpu < 20:
                    recommendations['rds_rightsizing'].append({
                        'db_instance': db_id,
                        'instance_class': db['DBInstanceClass'],
                        'avg_cpu': round(avg_cpu, 2),
                        'recommendation': 'Downsize or use Aurora Serverless'
                    })
        
        # Check for unused EBS volumes
        volumes = self.ec2.describe_volumes(
            Filters=[{'Name': 'status', 'Values': ['available']}]
        )
        for volume in volumes['Volumes']:
            recommendations['unused_volumes'].append({
                'volume_id': volume['VolumeId'],
                'size': volume['Size'],
                'type': volume['VolumeType'],
                'estimated_monthly_cost': round(volume['Size'] * 0.10, 2)  # Approximate cost
            })
        
        # Check for old snapshots
        snapshots = self.ec2.describe_snapshots(OwnerIds=['self'])
        old_date = datetime.now(snapshots['Snapshots'][0]['StartTime'].tzinfo) - timedelta(days=90)
        
        for snapshot in snapshots['Snapshots']:
            if snapshot['StartTime'] < old_date:
                recommendations['old_snapshots'].append({
                    'snapshot_id': snapshot['SnapshotId'],
                    'volume_size': snapshot['VolumeSize'],
                    'created': snapshot['StartTime'].strftime('%Y-%m-%d'),
                    'estimated_monthly_cost': round(snapshot['VolumeSize'] * 0.05, 2)
                })
        
        return recommendations
    
    def get_savings_plans_recommendations(self) -> Dict[str, Any]:
        """Get Savings Plans recommendations"""
        try:
            response = self.ce.get_savings_plans_purchase_recommendation(
                SavingsPlansType='COMPUTE_SP',
                TermInYears='THREE_YEAR',
                PaymentOption='ALL_UPFRONT',
                LookbackPeriodInDays='SIXTY_DAYS'
            )
            
            if 'SavingsPlansPurchaseRecommendation' in response:
                rec = response['SavingsPlansPurchaseRecommendation']
                return {
                    'estimated_monthly_savings': rec.get('EstimatedMonthlySavingsAmount', 0),
                    'estimated_savings_percentage': rec.get('EstimatedSavingsPercentage', 0),
                    'hourly_commitment': rec.get('HourlyCommitmentToPurchase', 0)
                }
        except Exception as e:
            print(f"Error getting Savings Plans recommendations: {e}")
        
        return {}
    
    def get_reserved_instance_recommendations(self) -> List[Dict]:
        """Get Reserved Instance recommendations"""
        recommendations = []
        
        try:
            response = self.ce.get_reservation_purchase_recommendation(
                Service='Amazon Elastic Compute Cloud - Compute',
                LookbackPeriodInDays='SIXTY_DAYS',
                TermInYears='THREE_YEAR',
                PaymentOption='ALL_UPFRONT'
            )
            
            for rec in response.get('Recommendations', []):
                for detail in rec.get('RecommendationDetails', []):
                    recommendations.append({
                        'instance_type': detail['InstanceDetails']['EC2InstanceDetails']['InstanceType'],
                        'instance_count': detail['RecommendedNumberOfInstancesToPurchase'],
                        'estimated_monthly_savings': detail['EstimatedMonthlySavingsAmount'],
                        'upfront_cost': detail['UpfrontCost']
                    })
        except Exception as e:
            print(f"Error getting RI recommendations: {e}")
        
        return recommendations
    
    def get_unused_resources(self) -> Dict[str, List]:
        """Identify completely unused resources"""
        unused = {
            'elastic_ips': [],
            'load_balancers': [],
            'nat_gateways': []
        }
        
        # Check for unassociated Elastic IPs
        eips = self.ec2.describe_addresses()
        for eip in eips['Addresses']:
            if 'InstanceId' not in eip and 'NetworkInterfaceId' not in eip:
                unused['elastic_ips'].append({
                    'allocation_id': eip.get('AllocationId'),
                    'public_ip': eip['PublicIp'],
                    'monthly_cost': 3.60  # Approximate cost
                })
        
        # Check for idle Load Balancers
        elb = boto3.client('elbv2')
        load_balancers = elb.describe_load_balancers()
        
        for lb in load_balancers['LoadBalancers']:
            target_groups = elb.describe_target_groups(
                LoadBalancerArn=lb['LoadBalancerArn']
            )
            
            idle = True
            for tg in target_groups['TargetGroups']:
                health = elb.describe_target_health(
                    TargetGroupArn=tg['TargetGroupArn']
                )
                if health['TargetHealthDescriptions']:
                    idle = False
                    break
            
            if idle:
                unused['load_balancers'].append({
                    'name': lb['LoadBalancerName'],
                    'type': lb['Type'],
                    'monthly_cost': 18.00 if lb['Type'] == 'application' else 22.50
                })
        
        return unused
    
    def generate_cost_allocation_report(self) -> pd.DataFrame:
        """Generate cost allocation by tags"""
        response = self.ce.get_cost_and_usage(
            TimePeriod={
                'Start': (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d'),
                'End': datetime.now().strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['UnblendedCost'],
            GroupBy=[
                {'Type': 'TAG', 'Key': 'Team'},
                {'Type': 'TAG', 'Key': 'Project'},
                {'Type': 'TAG', 'Key': 'Environment'}
            ]
        )
        
        allocations = []
        for result in response['ResultsByTime']:
            for group in result['Groups']:
                team = group['Keys'][0] if len(group['Keys']) > 0 else 'Untagged'
                project = group['Keys'][1] if len(group['Keys']) > 1 else 'Untagged'
                environment = group['Keys'][2] if len(group['Keys']) > 2 else 'Untagged'
                cost = float(group['Metrics']['UnblendedCost']['Amount'])
                
                allocations.append({
                    'Team': team,
                    'Project': project,
                    'Environment': environment,
                    'Cost': cost
                })
        
        return pd.DataFrame(allocations)
    
    def calculate_potential_savings(self, recommendations: Dict) -> float:
        """Calculate total potential monthly savings"""
        savings = 0
        
        # EC2 rightsizing (assume 30% reduction)
        for ec2 in recommendations.get('ec2_rightsizing', []):
            savings += 50  # Rough estimate per instance
        
        # RDS rightsizing (assume 40% reduction)
        for rds in recommendations.get('rds_rightsizing', []):
            savings += 100  # Rough estimate per instance
        
        # Unused volumes
        for vol in recommendations.get('unused_volumes', []):
            savings += vol['estimated_monthly_cost']
        
        # Old snapshots
        for snap in recommendations.get('old_snapshots', []):
            savings += snap['estimated_monthly_cost']
        
        return savings
    
    def generate_html_report(self, output_file: str = 'cost_report.html'):
        """Generate comprehensive HTML report"""
        # Gather all data
        monthly_costs = self.get_monthly_costs()
        underutilized = self.get_underutilized_resources()
        unused = self.get_unused_resources()
        savings_plans = self.get_savings_plans_recommendations()
        ri_recommendations = self.get_reserved_instance_recommendations()
        allocations = self.generate_cost_allocation_report()
        
        potential_savings = self.calculate_potential_savings(underutilized)
        
        # Generate HTML
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>IDP Cost Optimization Report</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; }}
                h1 {{ color: #232F3E; }}
                h2 {{ color: #FF9900; margin-top: 30px; }}
                table {{ border-collapse: collapse; width: 100%; margin-top: 10px; }}
                th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
                th {{ background-color: #232F3E; color: white; }}
                .savings {{ color: green; font-weight: bold; }}
                .warning {{ color: orange; }}
                .critical {{ color: red; }}
                .summary-box {{ 
                    background-color: #f0f0f0; 
                    padding: 15px; 
                    border-radius: 5px; 
                    margin: 20px 0;
                }}
            </style>
        </head>
        <body>
            <h1>IDP Cost Optimization Report</h1>
            <p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            
            <div class="summary-box">
                <h2>Executive Summary</h2>
                <p>Current Monthly Spend: <strong>${monthly_costs['Cost'].sum():.2f}</strong></p>
                <p>Potential Monthly Savings: <span class="savings">${potential_savings:.2f}</span></p>
                <p>Potential Savings Percentage: <span class="savings">{(potential_savings/monthly_costs['Cost'].sum()*100):.1f}%</span></p>
            </div>
            
            <h2>Monthly Cost Trend</h2>
            <table>
                <tr>
                    <th>Month</th>
                    <th>Total Cost</th>
                    <th>Top Service</th>
                </tr>
        """
        
        # Add monthly costs
        monthly_summary = monthly_costs.groupby('Month')['Cost'].sum().reset_index()
        for _, row in monthly_summary.iterrows():
            top_service = monthly_costs[monthly_costs['Month'] == row['Month']].nlargest(1, 'Cost')['Service'].values[0]
            html += f"""
                <tr>
                    <td>{row['Month']}</td>
                    <td>${row['Cost']:.2f}</td>
                    <td>{top_service}</td>
                </tr>
            """
        
        html += """
            </table>
            
            <h2>Optimization Recommendations</h2>
            
            <h3>1. Underutilized EC2 Instances</h3>
        """
        
        if underutilized['ec2_rightsizing']:
            html += """
            <table>
                <tr>
                    <th>Instance ID</th>
                    <th>Type</th>
                    <th>Avg CPU %</th>
                    <th>Recommendation</th>
                </tr>
            """
            for ec2 in underutilized['ec2_rightsizing']:
                html += f"""
                <tr>
                    <td>{ec2['instance_id']}</td>
                    <td>{ec2['instance_type']}</td>
                    <td class="warning">{ec2['avg_cpu']}%</td>
                    <td>{ec2['recommendation']}</td>
                </tr>
                """
            html += "</table>"
        else:
            html += "<p>No underutilized EC2 instances found.</p>"
        
        html += """
            <h3>2. Unused Resources</h3>
        """
        
        if unused['elastic_ips']:
            html += """
            <h4>Unassociated Elastic IPs</h4>
            <table>
                <tr>
                    <th>IP Address</th>
                    <th>Monthly Cost</th>
                </tr>
            """
            for eip in unused['elastic_ips']:
                html += f"""
                <tr>
                    <td>{eip['public_ip']}</td>
                    <td class="critical">${eip['monthly_cost']:.2f}</td>
                </tr>
                """
            html += "</table>"
        
        if unused['load_balancers']:
            html += """
            <h4>Idle Load Balancers</h4>
            <table>
                <tr>
                    <th>Name</th>
                    <th>Type</th>
                    <th>Monthly Cost</th>
                </tr>
            """
            for lb in unused['load_balancers']:
                html += f"""
                <tr>
                    <td>{lb['name']}</td>
                    <td>{lb['type']}</td>
                    <td class="critical">${lb['monthly_cost']:.2f}</td>
                </tr>
                """
            html += "</table>"
        
        if savings_plans:
            html += f"""
            <h3>3. Savings Plans Opportunity</h3>
            <div class="summary-box">
                <p>Estimated Monthly Savings: <span class="savings">${savings_plans.get('estimated_monthly_savings', 0):.2f}</span></p>
                <p>Savings Percentage: <span class="savings">{savings_plans.get('estimated_savings_percentage', 0):.1f}%</span></p>
                <p>Recommended Hourly Commitment: ${savings_plans.get('hourly_commitment', 0):.2f}</p>
            </div>
            """
        
        html += """
            <h2>Cost Allocation by Team</h2>
            <table>
                <tr>
                    <th>Team</th>
                    <th>Project</th>
                    <th>Environment</th>
                    <th>Monthly Cost</th>
                </tr>
        """
        
        for _, row in allocations.iterrows():
            html += f"""
                <tr>
                    <td>{row['Team']}</td>
                    <td>{row['Project']}</td>
                    <td>{row['Environment']}</td>
                    <td>${row['Cost']:.2f}</td>
                </tr>
            """
        
        html += """
            </table>
            
            <h2>Action Items</h2>
            <ol>
                <li>Review and rightsize underutilized EC2 and RDS instances</li>
                <li>Delete unused Elastic IPs and idle Load Balancers</li>
                <li>Implement Savings Plans for steady-state workloads</li>
                <li>Clean up old snapshots and unused EBS volumes</li>
                <li>Enforce tagging policy for better cost allocation</li>
                <li>Set up automated scheduling for non-production resources</li>
                <li>Review and optimize data transfer costs</li>
                <li>Consider spot instances for fault-tolerant workloads</li>
            </ol>
            
            <p><em>Report generated by IDP Cost Optimizer</em></p>
        </body>
        </html>
        """
        
        with open(output_file, 'w') as f:
            f.write(html)
        
        print(f"Report generated: {output_file}")
        return output_file

def main():
    parser = argparse.ArgumentParser(description='Generate IDP Cost Optimization Report')
    parser.add_argument('--profile', help='AWS profile to use')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--output', default='cost_report.html', help='Output file name')
    parser.add_argument('--months', type=int, default=6, help='Number of months to analyze')
    
    args = parser.parse_args()
    
    try:
        optimizer = CostOptimizer(profile=args.profile, region=args.region)
        optimizer.generate_html_report(args.output)
        print(f"Cost optimization report generated successfully: {args.output}")
    except Exception as e:
        print(f"Error generating report: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()