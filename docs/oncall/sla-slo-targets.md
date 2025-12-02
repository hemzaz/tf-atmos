# SLA/SLO Targets

## Service Level Agreements (SLAs)

### Customer-Facing SLAs

| Service | Availability | Response Time | Support Hours |
|---------|--------------|---------------|---------------|
| Production API | 99.9% | P95 < 500ms | 24/7 |
| Web Application | 99.9% | P95 < 2s | 24/7 |
| Background Jobs | 99.5% | Completion < 1h | Business hours |
| Support Portal | 99.5% | P95 < 3s | Business hours |

### SLA Calculations

**Monthly Uptime SLA:**
- 99.9% = 43.8 minutes downtime/month
- 99.95% = 21.9 minutes downtime/month
- 99.99% = 4.38 minutes downtime/month

## Service Level Objectives (SLOs)

### API Service SLOs

**Availability SLO: 99.95%**
- Measurement: Successful requests / Total requests
- Window: 30-day rolling
- Error budget: 0.05% = ~21.6 minutes/month

**Latency SLO:**
- P50 < 200ms
- P95 < 500ms
- P99 < 1000ms
- Window: 7-day rolling

**Error Rate SLO:**
- 5XX errors < 0.1%
- 4XX errors < 2%
- Window: 24-hour rolling

### Database SLOs

**Availability: 99.99%**
- Measurement: Instance available time
- Window: 30-day rolling

**Performance:**
- Read latency P95 < 10ms
- Write latency P95 < 50ms
- Connection pool utilization < 80%

**Replication:**
- Replica lag < 1 second
- Measurement: Every 5 minutes

### Infrastructure SLOs

**EKS Cluster:**
- Control plane availability: 99.95%
- Node availability: 99.9%
- Pod startup time P95 < 30s

**Load Balancer:**
- Availability: 99.99%
- Target response time P95 < 500ms
- Healthy target count > 2

## Service Level Indicators (SLIs)

### Request Success Rate
```
SLI = (Successful requests / Total requests) * 100
Successful = HTTP 200-299, 300-399
Failed = HTTP 500-599, timeouts, connection errors
```

**CloudWatch Query:**
```
fields @timestamp, statusCode
| filter statusCode >= 500
| stats count() as errors by bin(5m)
```

### Latency
```
SLI = P95 latency over 5-minute windows
Target: < 500ms
```

**CloudWatch Metrics:**
- Metric: TargetResponseTime
- Namespace: AWS/ApplicationELB
- Statistic: p95

### Availability
```
SLI = (Uptime minutes / Total minutes) * 100
Downtime = All health checks failing
```

**Measurement:**
- Route53 health checks
- CloudWatch Synthetics
- Internal monitoring

### Error Budget

**Calculation:**
```
Error Budget = (1 - SLO) * Total Requests

Example:
SLO: 99.95%
Total requests/month: 10M
Error budget: 0.05% * 10M = 5,000 errors
```

**Error Budget Policy:**
- **> 90% remaining:** Normal feature velocity
- **50-90% remaining:** Review deployment frequency
- **< 50% remaining:** Feature freeze, focus on reliability
- **0% remaining:** Mandatory reliability work until restored

## Monitoring and Alerting

### Critical Alerts (P0)
- SLI drops below 99%
- Error rate > 5%
- All instances down
- Database unavailable

### Warning Alerts (P1)
- SLI drops below 99.9%
- Error rate > 1%
- Latency P95 > 1000ms
- Error budget burn rate > 5x

### Advisory Alerts (P2)
- SLI drops below 99.95%
- Error rate > 0.5%
- Latency P95 > 750ms
- Error budget burn rate > 2x

## Error Budget Burn Rate

### Calculation
```
Burn Rate = (Errors in time window) / (Error budget for time window)

Fast burn: 1% of budget consumed in < 1 hour
Medium burn: 5% of budget consumed in < 1 day
Slow burn: 10% of budget consumed in < 1 week
```

### Burn Rate Alerts

**1-hour window (Fast burn):**
```
Burn rate > 14.4 = 100% budget consumed in 72 hours
Alert if: burn rate > 14.4 for 1 hour
```

**6-hour window (Medium burn):**
```
Burn rate > 6 = 100% budget consumed in 30 days
Alert if: burn rate > 6 for 6 hours
```

**24-hour window (Slow burn):**
```
Burn rate > 3 = 100% budget consumed in 30 days
Alert if: burn rate > 3 for 24 hours
```

## Measurement Windows

### Short Windows (1-24 hours)
- Catch fast-moving incidents
- Enable quick response
- May have false positives

### Medium Windows (3-7 days)
- Balance between speed and accuracy
- Primary operational metrics
- Guide feature development pace

### Long Windows (28-30 days)
- Match SLA reporting periods
- Show trends
- Guide strategic decisions

## Dashboard Links

**SLO Dashboard:**
`https://console.aws.amazon.com/cloudwatch/dashboards?#dashboards:name=production-slo`

**Error Budget Dashboard:**
`https://grafana.company.com/d/error-budget`

## SLO Review Process

### Weekly Review (Monday)
- Current SLO status
- Error budget remaining
- Incidents from past week
- Upcoming deployments

### Monthly Review (First Monday)
- 30-day SLO compliance
- Error budget consumption trend
- SLO adjustments needed
- Improvement initiatives

## SLO Targets by Environment

| Environment | Availability | Latency P95 | Error Rate |
|-------------|--------------|-------------|------------|
| Production | 99.95% | < 500ms | < 0.1% |
| Staging | 99.5% | < 1000ms | < 0.5% |
| Development | 99% | < 2000ms | < 1% |

## Exclusions

### Planned Maintenance
- Announced > 48 hours in advance
- Scheduled during low-traffic windows
- Maximum 2 hours duration
- Excluded from SLA calculations

### Dependency Failures
- AWS region outage
- Third-party API failures
- DNS provider issues
- Recorded but may be excluded from SLA

### Customer-Caused Issues
- Invalid API usage
- DDoS attacks
- Exceeding rate limits
- Excluded from SLA calculations

## Consequences of SLA Breach

### Internal
- Postmortem required
- Root cause analysis
- Prevention measures
- Runbook updates

### External (Customer SLA)
- Service credits per contract
- Customer notification
- Remediation plan
- Executive review

## Improvement Targets

### Quarterly Goals
- Reduce P50 latency by 10%
- Maintain error budget > 50%
- Zero customer-impacting P0 incidents
- MTTR < 30 minutes

### Annual Goals
- Achieve 99.99% availability
- P95 latency < 250ms
- Automate 90% of incident responses
- Zero SLA breaches

## References

- [Monitoring Dashboard](/components/terraform/monitoring/)
- [Incident Response](/docs/runbooks/incident-response.md)
- [On-Call Setup](/docs/oncall/oncall-setup.md)
- [Google SRE Book](https://sre.google/sre-book/service-level-objectives/)
