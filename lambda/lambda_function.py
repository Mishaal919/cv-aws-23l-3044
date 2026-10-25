"""cv-func-23l-3044: serve the CV from the private S3 bucket.

Bucket and prefix come from the environment variables BUCKET and PREFIX.
Credentials come from the execution role cv-lambda-role-23l-3044 (no keys).
"""
import base64
import json
import os
import time

import boto3

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]
PREFIX = os.environ["PREFIX"]

# path -> (object name under PREFIX, content type)
ROUTES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/style.css": ("style.css", "text/css"),
    "/cv.pdf": ("cv.pdf", "application/pdf"),
}

NOT_FOUND_PAGE = (
    "<!DOCTYPE html><html><head><title>404 Not Found</title></head>"
    "<body><h1>404 - Not Found</h1><p>There is nothing at this address. "
    '<a href="/">Back to the CV</a></p></body></html>'
)


def lambda_handler(event, context):
    start = time.time()
    path = event.get("rawPath") or "/"

    try:
        if path not in ROUTES:
            response = {
                "statusCode": 404,
                "headers": {"Content-Type": "text/html; charset=utf-8"},
                "body": NOT_FOUND_PAGE,
            }
        else:
            name, ctype = ROUTES[path]
            data = s3.get_object(Bucket=BUCKET, Key=PREFIX + name)["Body"].read()

            if name == "index.html":
                html = data.decode("utf-8").replace(
                    "{{HOSTED_ON}}", "Lambda " + context.function_name
                )
                response = {
                    "statusCode": 200,
                    "headers": {"Content-Type": ctype, "Cache-Control": "max-age=60"},
                    "body": html,
                }
            elif name == "cv.pdf":
                # binary: send base64 and set the flag so the URL decodes it
                response = {
                    "statusCode": 200,
                    "headers": {"Content-Type": ctype},
                    "body": base64.b64encode(data).decode("ascii"),
                    "isBase64Encoded": True,
                }
            else:
                response = {
                    "statusCode": 200,
                    "headers": {"Content-Type": ctype},
                    "body": data.decode("utf-8"),
                }
    except Exception as exc:  # S3 error etc.
        print(json.dumps({"error": str(exc)}))
        response = {
            "statusCode": 500,
            "headers": {"Content-Type": "text/plain"},
            "body": "Internal error",
        }

    # one JSON log line per request
    print(json.dumps({
        "fn": context.function_name,
        "path": path,
        "status": response["statusCode"],
        "ms": round((time.time() - start) * 1000, 1),
    }))
    return response
