# Host Your CV on AWS: Mishaal Rafique (23L-3044)

| | |
|---|---|
| **Name** | Mishaal Rafique |
| **Roll number** | 23L-3044 |
| **Region** | ap-southeast-2 (Asia Pacific, Sydney) |
| **EC2 address** | http://13.211.210.74 (instance `i-03be77256595e4f5e`, see note below) |
| **Lambda address** | https://mrhzgknncijcd3yxke6kmvw57q0ehokg.lambda-url.ap-southeast-2.on.aws/ |
| **Bucket** | `cv-23l-3044` (private) |

> **Note on the account and the EC2 instance.** I could not open my own AWS account because sign-up needs a payment card, so with my classmate's (23L-3055) permission I built everything in her account (`043475992098`) under my own names (`*-23l-3044`). Her account already runs one instance, so to avoid charging her I **terminated my EC2 instance after collecting all evidence**. `evidence.txt`, the access-denied output and the sync log below were all captured while it was running. The Lambda function and the bucket are still live.

## Architecture

```
                         Visitor (browser)
                 ┌───────────────┴────────────────┐
           HTTP :80                          HTTPS
                 │                                │
   ┌─────────────▼─────────────┐   ┌──────────────▼──────────────┐
   │ Security group            │   │ Lambda function URL         │
   │ cv-sg-23l-3044 (80 only)  │   │ auth type NONE              │
   └─────────────┬─────────────┘   └──────────────┬──────────────┘
                 │                                │
   ┌─────────────▼─────────────┐   ┌──────────────▼──────────────┐
   │ EC2 cv-ec2-23l-3044       │   │ Lambda cv-func-23l-3044     │
   │ t3.micro, AL2023, Apache  │   │ Python 3.14, 128 MB, 10 s   │
   │ sync-cv.sh every 5 min    │   │ env BUCKET, PREFIX          │
   │ role cv-ec2-role-23l-3044 │   │ role cv-lambda-role-23l-3044│
   │ (GetObject + ListBucket)  │   │ (GetObject + logs)          │
   └─────────────┬─────────────┘   └──────────────┬──────────────┘
      aws s3 sync│(every 5 min)       GetObject   │(per request)
                 └───────────────┬────────────────┘
                   ┌─────────────▼──────────────┐
                   │ S3 bucket cv-23l-3044      │
                   │ Block Public Access: all on│
                   │ Versioning: on             │
                   │ site/index.html, style.css,│
                   │ cv.pdf                     │
                   └────────────────────────────┘
        Direct S3 URL from a browser ──► 403 AccessDenied
```

**EC2 path:** the visitor's HTTP request passes the security group on port 80 and reaches Apache on the instance, which serves the files that `sync-cv.sh` copied from `s3://cv-23l-3044/site/` using the instance role, with `{{HOSTED_ON}}` already replaced by `EC2 <instance-id>`. **Lambda path:** the visitor's HTTPS request reaches the function URL, which invokes `cv-func-23l-3044`; the function reads the requested object from S3 with its role, replaces the placeholder with `Lambda cv-func-23l-3044` for the page, base64-encodes the PDF, and returns it with the right content type.

## Repository layout

```
README.md
collect-evidence.sh      evidence script (3 arguments; usage + exit 1 otherwise)
evidence.txt             output of my own run
site/                    index.html, style.css, cv.pdf (uploaded to s3://cv-23l-3044/site/)
ec2/                     user-data.sh, sync-cv.sh
lambda/                  lambda_function.py
iam/                     trust + permission policies of both roles
```

## Access denied from the instance

Run from a shell on the instance (EC2 Instance Connect), using only the instance role:

```
[ec2-user@ip-172-31-43-137 ~]$ aws s3 rm s3://cv-23l-3044/site/style.css
delete failed: s3://cv-23l-3044/site/style.css An error occurred (AccessDenied) when calling the DeleteObject operation: User: arn:aws:sts::043475992098:assumed-role/cv-ec2-role-23l-3044/i-03be77256595e4f5e is not authorized to perform: s3:DeleteObject on resource: "arn:aws:s3:::cv-23l-3044/site/style.css" because no identity-based policy allows the s3:DeleteObject action

[ec2-user@ip-172-31-43-137 ~]$ echo hacked > /tmp/x.html ; aws s3 cp /tmp/x.html s3://cv-23l-3044/site/index.html
upload failed: ../../tmp/x.html to s3://cv-23l-3044/site/index.html An error occurred (AccessDenied) when calling the PutObject operation: User: arn:aws:sts::043475992098:assumed-role/cv-ec2-role-23l-3044/i-03be77256595e4f5e is not authorized to perform: s3:PutObject on resource: "arn:aws:s3:::cv-23l-3044/site/index.html" because no identity-based policy allows the s3:PutObject action
```

## Last lines of /var/log/cv-sync.log

```
[ec2-user@ip-172-31-43-137 ~]$ sudo tail -n 10 /var/log/cv-sync.log
2026-10-25T19:48:20Z OK   sync s3://cv-23l-3044/site/ -> /var/www/html (i-03be77256595e4f5e)
2026-10-25T19:49:48Z OK   sync s3://cv-23l-3044/site/ -> /var/www/html (i-03be77256595e4f5e)
2026-10-25T19:54:48Z OK   sync s3://cv-23l-3044/site/ -> /var/www/html (i-03be77256595e4f5e)
2026-10-25T19:59:49Z OK   sync s3://cv-23l-3044/site/ -> /var/www/html (i-03be77256595e4f5e)
2026-10-25T20:04:49Z OK   sync s3://cv-23l-3044/site/ -> /var/www/html (i-03be77256595e4f5e)
2026-10-25T20:09:49Z OK   sync s3://cv-23l-3044/site/ -> /var/www/html (i-03be77256595e4f5e)
2026-10-25T20:14:50Z OK   sync s3://cv-23l-3044/site/ -> /var/www/html (i-03be77256595e4f5e)

[ec2-user@ip-172-31-43-137 ~]$ systemctl list-timers cv-sync.timer --no-pager
NEXT                        LEFT         LAST                        PASSED       UNIT          ACTIVATES
Sun 2026-10-25 20:19:49 UTC 2min 3s left Sun 2026-10-25 20:14:49 UTC 2min 56s ago cv-sync.timer cv-sync.service
```

The first line is the run from user data at boot; after that a systemd timer (`OnUnitActiveSec=5min`) runs the script every 5 minutes.

## Written answers

**1. Why do the instance and the function use roles instead of access keys? What could go wrong if the keys were in the user data?**
A role gives the instance and the function short-lived credentials that AWS rotates automatically, so there is no long-term secret to store, leak or rotate by hand. The permissions are attached to the role, so I can limit them to exactly `GetObject` on `site/` (and `ListBucket` for EC2). If access keys were in the user data, anyone who can read the instance's user data (through the console, the API, or the metadata service from inside the instance) could copy them. The keys would keep working from anywhere on the internet until someone deactivated them, and if the repository is public they would be exposed to everyone, possibly with far more permissions than the site needs.

**2. Someone pastes the S3 address of index.html into a browser. What do they see, and which setting causes that?**
They get an XML error page with `<Code>AccessDenied</Code>` (HTTP 403), as shown in the `endpoints` section of `evidence.txt`. This is caused by Block Public Access being fully on, together with having no bucket policy or ACL that grants anything to everyone. An anonymous browser request has no identity that any policy allows, so S3 refuses it. Only the two roles are allowed to read the objects.

**3. Explain in your own words the permission on the function URL that lets anyone call it. Why is that acceptable for the function but not for the bucket?**
When I created the function URL with auth type NONE, the console added a resource-based policy statement (`FunctionURLAllowPublicAccess`) with principal `*`, allowing `lambda:InvokeFunctionUrl` on my function only when the auth type is NONE, plus a matching `lambda:InvokeFunction` statement limited to calls that come through the function URL. In other words, anyone on the internet may send an HTTP request to that URL and have the function run. That is acceptable because the function is a controlled gate: it only answers four fixed paths, returns 404 for everything else, and its own role can only read `site/`, so callers can never list, change or delete anything. Opening the bucket instead would expose every object and any future file directly, with no code in between to decide what is served.

**4. Compare the two paths. What do you pay for when nobody visits the site? What happens if the traffic grows a hundred times?**
With EC2 I pay for the instance every hour it runs, plus its public IPv4 address and its EBS disk, even if nobody visits (free tier covers about one small instance). With Lambda I pay only per request and per millisecond of run time, so with no visitors the cost is basically zero apart from the tiny S3 storage. If traffic grows a hundred times, the single t3.micro would eventually run out of CPU or network capacity and slow down or fail, unless I add a load balancer, an Auto Scaling group or a bigger instance. Lambda scales automatically by running more copies at the same time (up to the account's concurrency limit), and the bill grows in proportion to the number of requests.

**5. You delete the EC2 instance. What do you lose and what do you still have?**
I lose the instance itself, its root EBS volume (deleted on termination by default), the Apache setup, the local copy of the site and `/var/log/cv-sync.log`, and its public IP address, which goes back to AWS and will not come back. I still have the S3 bucket with all three files and their versions, both IAM roles and their policies, the security group (until I delete it), the Lambda function, its URL and its logs. Because the user data and scripts are in this repository, I can launch a new instance with the same user data and the site comes back, but with a new IP address.

## Sources and adaptation

- AWS documentation: *IAM roles for Amazon EC2*, *Use IMDSv2*, *Lambda function URLs*, *Return binary data from Lambda (isBase64Encoded)*, *Amazon S3 Block Public Access*, and *systemd timers* on Amazon Linux 2023.
- The scripts, policies and Lambda code were drafted with help from an AI assistant (Claude) and then deployed, tested and checked by me step by step in the AWS console. I can explain each file.
- No access keys or passwords are stored anywhere in this repository, the user data, or the function configuration.
