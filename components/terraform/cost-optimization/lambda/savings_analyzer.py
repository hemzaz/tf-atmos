"""
Savings Plans / Reserved Instance Recommendation Analyzer Lambda Function

Pulls Cost Explorer Savings Plans, Reserved Instance and rightsizing
recommendations, plus AWS Compute Optimizer recommendations, and publishes a
summary to the cost-alerts SNS topic. Runs weekly (see the
aws_cloudwatch_event_rule.savings_analysis schedule in lambda.tf).

Every recommendation call is wrapped individually: Compute Optimizer returns
an error until an account has opted in / has enough utilization history, and
a missing recommendation type should not stop the others from being
gathered or from reaching SNS.
"""

import boto3
import json
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ce = boto3.client('ce')
compute_optimizer = boto3.client('compute-optimizer')
sns = boto3.client('sns')

# SNS caps a Publish Message at 256 KiB (262144 bytes) total; leave headroom
# for the Subject and JSON overhead added after truncation.
SNS_MESSAGE_SIZE_LIMIT_BYTES = 256 * 1024
SNS_MESSAGE_TRUNCATION_MARGIN_BYTES = 1024
MAX_ITEMS_PER_RECOMMENDATION_LIST = 50


def _cap_list(value):
    """Bound an unbounded recommendation list so a large account's
    Compute Optimizer or RI recommendation count alone cannot push a single
    recommendation source past SNS's message size limit."""
    if isinstance(value, list) and len(value) > MAX_ITEMS_PER_RECOMMENDATION_LIST:
        return value[:MAX_ITEMS_PER_RECOMMENDATION_LIST] + [
            {'truncated': True, 'omitted_count': len(value) - MAX_ITEMS_PER_RECOMMENDATION_LIST}
        ]
    return value


def _bounded_summary_message(summary):
    """Serialize summary, falling back to a smaller, indent-free encoding
    and then to an errors-only summary if it still exceeds SNS's limit."""
    message = json.dumps(summary, indent=2, default=str)
    if len(message.encode('utf-8')) <= SNS_MESSAGE_SIZE_LIMIT_BYTES - SNS_MESSAGE_TRUNCATION_MARGIN_BYTES:
        return message

    compact = json.dumps(summary, default=str)
    if len(compact.encode('utf-8')) <= SNS_MESSAGE_SIZE_LIMIT_BYTES - SNS_MESSAGE_TRUNCATION_MARGIN_BYTES:
        return compact

    fallback = {
        'environment': summary.get('environment'),
        'errors': summary.get('errors'),
        'truncated': True,
        'truncation_reason': 'serialized recommendations exceeded the SNS message size limit',
        'recommendation_sources': list(summary.get('recommendations', {}).keys()),
    }
    return json.dumps(fallback, default=str)


def handler(event, context):
    environment = os.environ.get('ENVIRONMENT', 'unknown')
    sns_topic = os.environ['SNS_TOPIC']

    logger.info(f"Starting savings analysis: Environment={environment}")

    recommendations = {}
    errors = {}

    for name, fn in (
        ('savings_plans', get_savings_plans_recommendation),
        ('reserved_instances', get_reservation_recommendation),
        ('rightsizing', get_rightsizing_recommendation),
        ('compute_optimizer_ec2', get_compute_optimizer_ec2_recommendations),
        ('compute_optimizer_asg', get_compute_optimizer_asg_recommendations),
        ('compute_optimizer_ebs', get_compute_optimizer_ebs_recommendations),
    ):
        try:
            recommendations[name] = _cap_list(fn())
        except Exception as e:
            logger.warning(f"Could not gather {name} recommendations: {str(e)}")
            errors[name] = str(e)

    summary = {
        'environment': environment,
        'recommendations': recommendations,
        'errors': errors,
    }

    try:
        sns.publish(
            TopicArn=sns_topic,
            Subject=f"[{environment}] Weekly savings analysis",
            Message=_bounded_summary_message(summary),
        )
        logger.info("Published savings analysis summary to SNS")
    except Exception as e:
        # Re-raise rather than returning a 500: EventBridge ignores an
        # invoked Lambda's return value, so catching-and-returning would
        # leave the function's Errors metric at zero and any alarm on it
        # silent even though the weekly summary never reached SNS.
        logger.error(f"Failed to publish savings analysis summary: {str(e)}")
        raise

    if not recommendations:
        # Every recommendation source failed (e.g. missing Cost Explorer /
        # Compute Optimizer grants). The errors-only summary above was
        # still published for visibility, but returning 200 here would
        # leave the Errors metric and its alarm silent for a misconfigured
        # analyzer, exactly the failure this function exists to catch.
        raise RuntimeError(f"All recommendation sources failed: {errors}")

    return {'statusCode': 200, 'body': json.dumps(summary, default=str)}


def get_savings_plans_recommendation():
    response = ce.get_savings_plans_purchase_recommendation(
        SavingsPlansType='COMPUTE_SP',
        TermInYears='ONE_YEAR',
        PaymentOption='NO_UPFRONT',
        LookbackPeriodInDays='THIRTY_DAYS',
    )
    summary = response.get('SavingsPlansPurchaseRecommendation', {}).get(
        'SavingsPlansPurchaseRecommendationSummary', {}
    )
    return {
        'estimated_monthly_savings': summary.get('EstimatedMonthlySavingsAmount'),
        'estimated_savings_percentage': summary.get('EstimatedSavingsPercentage'),
        'hourly_commitment_to_purchase': summary.get('HourlyCommitmentToPurchase'),
        'currency_code': summary.get('CurrencyCode'),
    }


def get_reservation_recommendation():
    response = ce.get_reservation_purchase_recommendation(
        Service='Amazon Elastic Compute Cloud - Compute',
        LookbackPeriodInDays='THIRTY_DAYS',
        TermInYears='ONE_YEAR',
        PaymentOption='NO_UPFRONT',
    )
    summary = response.get('Metadata', {})
    recommendations = response.get('Recommendations', [])
    return {
        'recommendation_id': summary.get('RecommendationId'),
        'recommendation_count': len(recommendations),
        'recommendations': [
            {
                'instance_details': r.get('RecommendationDetails', [{}])[0].get('InstanceDetails'),
                'estimated_monthly_savings': r.get('RecommendationDetails', [{}])[0].get(
                    'EstimatedMonthlySavingsAmount'
                ),
            }
            for r in recommendations
        ],
    }


def get_rightsizing_recommendation():
    response = ce.get_rightsizing_recommendation(Service='AmazonEC2')
    summary = response.get('Summary', {})
    return {
        'total_recommendation_count': summary.get('TotalRecommendationCount'),
        'estimated_total_monthly_savings': summary.get('EstimatedTotalMonthlySavingsAmount'),
        'savings_currency_code': summary.get('SavingsCurrencyCode'),
    }


def get_compute_optimizer_ec2_recommendations():
    response = compute_optimizer.get_ec2_instance_recommendations()
    return [
        {
            'instance_arn': r.get('instanceArn'),
            'finding': r.get('finding'),
            'current_instance_type': r.get('currentInstanceType'),
        }
        for r in response.get('instanceRecommendations', [])
    ]


def get_compute_optimizer_asg_recommendations():
    response = compute_optimizer.get_auto_scaling_group_recommendations()
    return [
        {
            'auto_scaling_group_arn': r.get('autoScalingGroupArn'),
            'finding': r.get('finding'),
        }
        for r in response.get('autoScalingGroupRecommendations', [])
    ]


def get_compute_optimizer_ebs_recommendations():
    response = compute_optimizer.get_ebs_volume_recommendations()
    return [
        {
            'volume_arn': r.get('volumeArn'),
            'finding': r.get('finding'),
        }
        for r in response.get('volumeRecommendations', [])
    ]
