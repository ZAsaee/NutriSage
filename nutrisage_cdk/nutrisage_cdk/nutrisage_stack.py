from pathlib import Path
from aws_cdk import (
    Stack,
    RemovalPolicy,
    aws_iam as iam,
    aws_s3 as s3,
    aws_sagemaker as sagemaker
)
from constructs import Construct
import json
import os


class NutriSageStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs):
        super().__init__(scope, construct_id, **kwargs)

    proj = os.getenv("PROJECT", "nutrisage")
    account = os.getenv("AWS_ACCOUNT_ID")

    # --- S3 Buckets (import existing - created by bootstrap.sh) -------------
    tiers = ["raw", "processed", "models"]
    buckets = {
        t: s3.Bucket.from_bucket_name(
            self, f"{t.capitalize()}Bucket", bucket_name=f"{proj}-{t}-{account}"
        )
        for t in tiers
    }

    # --- SageMaker execution role (least‑privilege dev role) -----------------
    sm_role = iam.Role(
        self,
        "NutriSageSageMakerRole",
        assumed_by=iam.ServicePrincipal("sagemaker.amazonaws.com"),
        description="Executes processing & training jobs for NutriSage",
        managed_policies=[
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonSageMakerFullAccess"
            )
        ],
    )

    # --- Minimal empty pipeline (placeholder) -------------------------------
    pipeline_definition = {
        "Version": "2020-12-01",
        "Metadata": {"Project": proj},
        "PipelineExperimentConfig": {"ExperimentName": f"{proj}-exp"},
        "Steps": [],  # will be filled Day‑3 onward
    }

    sagemaker.CfnPipeline(
        self,
        "NutriSagePipeline",
        pipeline_name=f"{proj}-pipeline",
        role_arn=sm_role.role_arn,
        pipeline_definition=json.dumps(pipeline_definition),
    )
