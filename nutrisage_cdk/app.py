#!/usr/bin/env python3
# nutrisage_cdk/app.py
import aws_cdk as cdk
import boto3
import os
from nutrisage_cdk.NutriSageStack import NutriSageStack
from nutrisage_cdk.load_env import load_env
load_env()


# --- Fallbacks in case .env is missing or partial ---------------------------
os.environ.setdefault(
    "AWS_ACCOUNT_ID",
    boto3.client("sts").get_caller_identity()["Account"],
)
os.environ.setdefault(
    "AWS_REGION",
    boto3.session.Session().region_name or "us-east-1",
)

env = cdk.Environment(
    account=os.environ["AWS_ACCOUNT_ID"],
    region=os.environ["AWS_REGION"],
)

app = cdk.App()
NutriSageStack(app, "NutriSageStack", env=env)
app.synth()
