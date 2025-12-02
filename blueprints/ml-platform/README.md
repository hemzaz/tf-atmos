# ML Platform Blueprint

End-to-end machine learning platform infrastructure.

## Architecture

```
    ┌─────────────────────────────────────────────────────────────────────┐
    │                        SageMaker Domain                              │
    │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐       │
    │  │  Studio   │  │   Data    │  │  Canvas   │  │ Notebooks │       │
    │  │   IDE     │  │ Wrangler  │  │  (No-Code)│  │  (Dev)    │       │
    │  └───────────┘  └───────────┘  └───────────┘  └───────────┘       │
    └─────────────────────────────────────────────────────────────────────┘
                                    │
    ┌───────────────────────────────┼───────────────────────────────────┐
    │                               │                                   │
    │  ┌─────────────┐   ┌─────────┴─────────┐   ┌─────────────┐      │
    │  │   Feature   │   │    SageMaker      │   │    Model    │      │
    │  │    Store    │◄──┤    Pipelines      │──►│   Registry  │      │
    │  │  (Online/   │   │  (Orchestration)  │   │ (Versioning)│      │
    │  │   Offline)  │   │                   │   │             │      │
    │  └─────────────┘   └─────────────────────   └──────┬──────┘      │
    │                                                    │              │
    └────────────────────────────────────────────────────┼──────────────┘
                                                         │
                          ┌──────────────────────────────┼──────────────┐
                          │                              │              │
                          ▼                              ▼              ▼
                   ┌──────────────┐            ┌──────────────┐  ┌──────────┐
                   │   Endpoint   │            │  Serverless  │  │  Batch   │
                   │  (Real-time) │            │   Endpoint   │  │Transform │
                   └──────────────┘            └──────────────┘  └──────────┘
```

## Components

| Component | Purpose |
|-----------|---------|
| SageMaker Domain | ML development environment |
| Feature Store | Feature engineering and serving |
| Pipelines | ML workflow orchestration |
| Model Registry | Model versioning and governance |
| Endpoints | Model serving (real-time/serverless) |
| MLflow | Experiment tracking |

## Quick Start

1. **Deploy Infrastructure**:
```bash
atmos terraform apply vpc -s <stack>
atmos terraform apply s3-data -s <stack>
atmos terraform apply s3-models -s <stack>
```

2. **Deploy SageMaker**:
```bash
atmos terraform apply sagemaker-domain -s <stack>
atmos terraform apply sagemaker-feature-store -s <stack>
```

3. **Deploy Experiment Tracking**:
```bash
atmos terraform apply rds -s <stack>
atmos terraform apply eks -s <stack>
atmos terraform apply mlflow -s <stack>
```

## Cost Estimate

| Use Case | Monthly Cost |
|----------|--------------|
| Development | $200-500 |
| Training (10 jobs) | $500-2,000 |
| Inference (real-time) | $500-3,000 |
| Full Platform | $2,000-10,000+ |

## ML Workflow

### 1. Data Preparation

```python
import sagemaker
from sagemaker.feature_store.feature_group import FeatureGroup

feature_group = FeatureGroup(
    name="customer-features",
    sagemaker_session=sagemaker.Session()
)

# Ingest features
feature_group.ingest(
    data_frame=df,
    max_workers=4
)
```

### 2. Training Pipeline

```python
from sagemaker.workflow.pipeline import Pipeline
from sagemaker.workflow.steps import TrainingStep

training_step = TrainingStep(
    name="Training",
    estimator=estimator,
    inputs={
        "train": TrainingInput(s3_data=train_path),
        "validation": TrainingInput(s3_data=val_path)
    }
)

pipeline = Pipeline(
    name="training-pipeline",
    steps=[processing_step, training_step, evaluation_step]
)
```

### 3. Model Deployment

```python
from sagemaker.model import Model

model = Model(
    image_uri=image_uri,
    model_data=model_artifact,
    role=role
)

# Real-time endpoint
predictor = model.deploy(
    instance_type="ml.m5.large",
    initial_instance_count=2,
    endpoint_name="my-model-endpoint"
)

# Or serverless
predictor = model.deploy(
    serverless_inference_config=ServerlessInferenceConfig(
        memory_size_in_mb=2048,
        max_concurrency=50
    )
)
```

## Feature Store

### Online Store (Real-time)
- Sub-millisecond latency
- DynamoDB backend
- Feature serving for inference

### Offline Store (Training)
- S3 + Glue Catalog
- Historical features
- Time travel queries

```python
# Get online features
record = feature_group.get_record(
    record_identifier_value_as_string="customer_123"
)

# Query offline features
query = feature_group.athena_query()
df = query.run(
    query_string="""
        SELECT *
        FROM "customer-features"
        WHERE event_time >= '2024-01-01'
    """,
    output_location=f"s3://{bucket}/query-results/"
).as_dataframe()
```

## MLflow Integration

```python
import mlflow

mlflow.set_tracking_uri("http://mlflow.internal")
mlflow.set_experiment("my-experiment")

with mlflow.start_run():
    mlflow.log_params(hyperparameters)
    mlflow.log_metrics({"accuracy": 0.95, "f1": 0.92})
    mlflow.sklearn.log_model(model, "model")
```

## Best Practices

1. **Experiment Tracking**: Log all experiments
2. **Feature Versioning**: Use feature store
3. **Model Registry**: Version all models
4. **A/B Testing**: Use multi-model endpoints
5. **Monitoring**: Track model drift
