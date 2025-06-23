import os
import aws_cdk as cdk
from nutrisage_cdk.nutrisage_stack import NutriSageStack

env = cdk.Environment(
    account=os.getenv("AWS_ACCOUNT_ID"),
    region=os.getenv("AWS_REGION", "us-east-1")
)

app = cdk.App()
NutriSageStack(app, "NutriSageStack", env=env)
app.synth()
