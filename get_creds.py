import boto3
import sys
import os

profile = sys.argv[1]
session = boto3.Session(profile_name=profile)
creds = session.get_credentials().get_frozen_credentials()

print(f"export AWS_ACCESS_KEY_ID={creds.access_key}")
print(f"export AWS_SECRET_ACCESS_KEY={creds.secret_key}")
print(f"export AWS_SESSION_TOKEN={creds.token}")
