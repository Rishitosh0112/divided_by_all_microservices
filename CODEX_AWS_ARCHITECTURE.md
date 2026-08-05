# Divided By All — AWS Architecture

This is the agreed target architecture for Divided By All. It includes the current User and
Groups services and the planned Expense and Notification services.

The first deployment is deliberately smaller: User, Groups, API gateway, frontend, and their
databases. Expense, Notification, Kafka, Route 53, and CloudFront are added in later
stages. This avoids paying for infrastructure before there is an application using it.

## Naming convention

This document writes an AWS service's full name on its first mention, followed by its commonly
used abbreviation. Later references use the abbreviation.

```text
Amazon Elastic Container Service (ECS)
Amazon Elastic Compute Cloud (Amazon EC2)
Application Load Balancer (ALB)
Auto Scaling group (ASG)
Amazon Elastic Container Registry (ECR)
Amazon Relational Database Service (Amazon RDS)
Amazon Managed Streaming for Apache Kafka (Amazon MSK)
```

## Decisions

| Concern | Chosen approach |
|---|---|
| Region | `ap-south-1` (Mumbai) |
| Container registry | Private Amazon Elastic Container Registry (ECR) repositories |
| Container orchestration | Amazon Elastic Container Service (ECS) |
| Container compute | ECS on Amazon Elastic Compute Cloud (Amazon EC2), not Fargate |
| EC2 capacity scaling | EC2 Auto Scaling group (ASG) attached through an ECS Capacity Provider |
| Application-task scaling | ECS Service Auto Scaling, independently for each service |
| Public HTTP load balancer | Application Load Balancer (ALB) |
| Current HTTP gateway | Existing Nginx API-gateway container, deployed as its own ECS service |
| Current authentication | Existing User-service JWT and cookie flow; Cognito is not part of the first deployment |
| User data | Amazon DocumentDB when the cloud database is introduced |
| Groups and Expense data | Amazon Relational Database Service (Amazon RDS) for PostgreSQL; one database/schema ownership boundary per service |
| Domain events | Apache Kafka, using Amazon Managed Streaming for Apache Kafka (Amazon MSK) when event-driven services are introduced |
| DNS and CDN | Route 53 and CloudFront after the ALB deployment is working and a domain is available |
| Secrets and encryption | AWS Secrets Manager, AWS Identity and Access Management (IAM) roles, AWS Key Management Service (KMS) |
| Logs, metrics, alarms | Amazon CloudWatch; OpenTelemetry/AWS X-Ray can be added later |

## Phase 1 — Current application deployment

Phase 1 deploys only the application that exists today: frontend shell, Client MFE, Nginx API
gateway, User service, and Groups service. It proves the container, networking, load-balancing,
and independent-scaling design before introducing event-driven services.

### Phase 1 request flow

```text
Browser
  |
  v
Application Load Balancer (ALB)
  |
  +--> /             -> frontend-shell Amazon Elastic Container Service (ECS) service
  +--> /mfe/*        -> client-mfe ECS service
  `--> /auth/*, /profiles/*, /groups/*
                         -> Nginx API-gateway ECS service
                              |
                              v
                         ECS Service Connect
                              |
                              +--> User-service ECS service -> Amazon DocumentDB
                              `--> Groups-service ECS service -> Amazon RDS for PostgreSQL
```

The ALB is the one public entrance for both the frontend and the APIs. The frontend is not in the
path of every API call. A browser page request goes to the frontend shell; an API request goes to
the Nginx API gateway, which calls User or Groups privately through ECS Service Connect.

### Phase 1 compute and scaling flow

```text
ECS service autoscaling
  -> changes the number of application tasks/containers
  -> ECS Capacity Provider detects whether EC2 capacity is sufficient
  -> EC2 Auto Scaling group (ASG) adds or removes Amazon EC2 instances
  -> ECS scheduler places tasks on the available EC2 instances
```

Each service scales independently. For example, User service can grow from one to three tasks
without adding Groups-service tasks. The ASG supplies the underlying Amazon EC2 capacity needed by
all ECS services.

### Phase 1 network boundaries

```text
VPC across two Availability Zones
  |- public subnets: internet-facing ALB and initial ECS/EC2 task capacity
  `- private subnets: Amazon RDS PostgreSQL and Amazon DocumentDB
```

The learning deployment omits a Network Address Translation (NAT) Gateway initially to avoid its
fixed hourly cost. Security groups still prevent direct internet access to ECS tasks and databases.
The production-hardening phase moves ECS tasks to private subnets and adds NAT gateways or Virtual
Private Cloud (VPC) endpoints as appropriate.

## Scaling model

There are two separate scaling layers.

```text
ECS Service Auto Scaling                 ECS Capacity Provider + ASG
controls container/task count            controls EC2 instance capacity

user-service: 1 task -> 3 tasks          EC2 instances: 1 -> 2 when tasks need space
groups-service: stays at 1 task          EC2 instances: 2 -> 1 when capacity is unused
```

ECS decides how many tasks each service needs from its CPU, memory, or request metrics. The ECS
scheduler places those tasks on registered EC2 instances. If there is insufficient capacity, the
ECS Capacity Provider coordinates with the ASG to launch another EC2 instance, within the ASG
minimum and maximum limits.

For the cost-controlled learning environment, start the ASG at:

```text
minimum: 1     desired: 1     maximum: 2
```

## Phase 1 component topology

```text
GitHub Actions
     |
     v
Amazon ECR (one private repository per image)
     |
     v
ECS task definitions and ECS services
     |
     v
ECS Cluster -- ECS Capacity Provider -- ASG -- EC2 container instances

Internet
     |
     v
Public Application Load Balancer
     |
     +--> frontend-shell ECS service
     |
     +--> client-mfe ECS service
     |
     +--> api-gateway ECS service (Nginx)
                    |
                    +--> ECS Service Connect --> user-service ECS service --> DocumentDB
                    |
                    +--> ECS Service Connect --> groups-service ECS service --> RDS PostgreSQL
```

The ALB is the only public entry point for application HTTP traffic. It performs health checks and
sends traffic only to healthy ECS tasks. The Nginx API-gateway container preserves the gateway
behaviour already used locally: it validates requests with User service and forwards group routes
to Groups service.

The Client MFE remains a separate ECS service and ECR image. Its `remoteEntry.js` URL is supplied
to the frontend shell through `NEXT_PUBLIC_MFE_REMOTE_URL`. Because `NEXT_PUBLIC_*` values are
embedded when Next.js builds the frontend image, GitHub Actions must pass the MFE public URL at
image-build time (or we must later add a runtime configuration mechanism). During ALB configuration
we will create a dedicated listener rule and target group for the MFE assets, then set the build
variable to that public URL. Later, static MFE assets can move to S3 and CloudFront without
changing the frontend-shell ownership boundary.

The user-facing ALB DNS name is used first. It looks like this:

```text
http://divided-by-all-alb-123456.ap-south-1.elb.amazonaws.com
```

No domain, Route 53 record, CloudFront distribution, or HTTPS certificate is required to prove
that this first deployment works.

## Production edge topology — added after the first deployment

```text
Users
  |
  v
Route 53 DNS
  |
  v
CloudFront + AWS WAF
  |
  +--> cached frontend/static assets
  |
  +--> dynamic requests (not cached)
           |
           v
       Public ALB --> ECS frontend and API-gateway services
```

- Route 53 maps a domain such as `app.example.com` to CloudFront.
- CloudFront reduces latency and origin load by caching safe frontend assets.
- AWS WAF protects public HTTP endpoints.
- ACM provides HTTPS certificates. A CloudFront certificate must be requested in `us-east-1`;
  an ALB certificate is requested in the ALB's region (`ap-south-1`).

## Service ownership

### User service

- Owns signup, login, logout, JWT validation, and user profiles.
- Runs as an ECS service and scales independently.
- Owns its DocumentDB data. No other service reads its collections directly.
- Current routes: `/auth/*` and `/profiles/*`.

### Groups service

- Owns groups, members, invitations, and creator authorization.
- Runs as an ECS service and scales independently.
- Owns its PostgreSQL data in RDS.
- Current routes: `/groups/*`.
- Publishes group membership events to Kafka when eventing is introduced.

### Expense service — future

- Owns expense lifecycle, participant snapshots, Equal/Exact split strategies, obligations,
  group balances, confirmed settlements, and settlement history.
- Owns one PostgreSQL database and transactional outbox for all of those financial records.
- Consumes relevant group membership events and publishes versioned expense and settlement events
  for Notification Service.
- Routes: `/expenses/*`, `/balances/*`, and `/settlements/*`.

### Notification service — future

- Owns notification preferences, inbox state, delivery attempts, and templates.
- Consumes Kafka events from Groups and Expense.
- Uses DynamoDB for a user-oriented notification inbox and SES for email delivery.
- Routes: `/notifications/*`.

## Kafka event architecture

Kafka replaces SQS and EventBridge in this design. When event-driven services are built, Amazon
MSK is the managed AWS Kafka offering we will use rather than operating Kafka brokers ourselves.

```text
Service database transaction
  |- domain data changes
  `- outbox event is stored
             |
             v
       outbox publisher
             |
             v
       Amazon MSK / Kafka topics
             |
   +---------+-------------------+
   |                             |
Expense consumer group      Notification consumer group
   |                             |
Expense service             Notification service
```

- Producers publish versioned events such as `group.member-added.v1` and `expense.created.v1`.
- Each consuming service has its own Kafka consumer group, so it receives its own copy of an event
  stream while instances of that one service share the work.
- Delivery is at-least-once. Consumers must store processed event IDs or otherwise make their
  state changes idempotent.
- Retry and dead-letter handling use explicit retry and dead-letter Kafka topics, plus alarms on
  consumer lag and failed processing.
- Kafka is not deployed in the first User/Groups release. MSK has a meaningful running cost, so it
  is introduced with the first producer/consumer pair—normally Groups and Expense.

## Networking and security

Target production networking spans at least two Availability Zones:

```text
VPC
|- public subnets: ALB and NAT gateways
`- private subnets: ECS EC2 instances/tasks, RDS, DocumentDB, and MSK
```

- The ALB security group accepts HTTP/HTTPS from the internet (or only CloudFront after it is
  introduced).
- ECS Service Connect provides stable internal DNS names for service-to-service calls even when
  ECS replaces a task and its private IP changes. The gateway calls User and Groups through those
  internal names; it never depends on an individual task IP.
- ECS service security groups accept application traffic only from the ALB or the gateway service,
  as appropriate.
- Database and MSK security groups accept traffic only from the specific ECS service security
  groups that need them.
- GitHub Actions assumes an AWS IAM role using OIDC; it does not store long-lived AWS access keys.
- ECS task roles read only their required Secrets Manager secrets and write only their required
  logs or AWS resources.

For the low-cost learning launch, we may temporarily use public subnets for the ECS container
instances to avoid NAT Gateway charges. Security groups still prevent direct application access.
This is a cost-saving lab choice, not the final production network layout above.

## Delivery and operations

```text
GitHub push
  -> GitHub Actions tests and builds images
  -> image tagged with immutable Git commit SHA
  -> image pushed to ECR
  -> new ECS task definition revision
  -> ECS rolling deployment
  -> ALB health checks validate new tasks
```

- Every service has its own ECR repository, ECS service, health endpoint, CloudWatch log group,
  dashboard, and autoscaling policy.
- ECS service autoscaling is configured per service; User and Groups never have to scale together.
- The ASG scales EC2 capacity separately from the ECS services.
- Carry a `correlationId` through HTTP logs and future Kafka event headers.

## Build order

1. Create ECR repositories and a GitHub OIDC role; change the existing pipeline to push images to
   ECR rather than SSH into an EC2 instance.
2. Create VPC networking, security groups, an ALB, ECS cluster, launch template, ASG, and ECS
   Capacity Provider.
3. Create RDS PostgreSQL, DocumentDB, and their Secrets Manager secrets before starting the User
   and Groups ECS services. Migrate service connection settings from local Docker databases.
4. Deploy the frontend shell, Client MFE, API gateway, User, and Groups ECS services; configure
   Service Connect and ALB target groups, then test through the ALB DNS name.
5. Attach a domain in Route 53, create ACM certificates, then add CloudFront and WAF.
6. Build Expense with balances, settlements, and outbox publishing, then introduce Amazon MSK/Kafka.
7. Build Notification as a Kafka consumer with DynamoDB and SES.
8. Add multi-AZ hardening, disaster recovery, and multi-region design only after the single-region
   system is measured and stable.
