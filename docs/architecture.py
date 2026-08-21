"""Regenerate docs/architecture.png:

    pip install diagrams
    brew install graphviz    # or: apt install graphviz
    python docs/architecture.py
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.analytics import Athena, Glue, GlueCrawlers
from diagrams.aws.compute import EC2, Lambda
from diagrams.aws.database import Dynamodb
from diagrams.aws.integration import SNS, SQS
from diagrams.aws.network import APIGateway
from diagrams.aws.storage import S3
from diagrams.onprem.client import Client

graph_attr = {
    "fontsize": "16",
    "bgcolor": "transparent",
    "pad": "0.5",
    "splines": "spline",
}

with Diagram(
    "Serverless CSV to Parquet Pipeline",
    filename="docs/architecture",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    client = Client("Client")

    with Cluster("Ingest"):
        api = APIGateway("API Gateway")
        uploader = Lambda("Upload handler")
        raw = S3("S3 - raw")
        meta = Dynamodb("DynamoDB\nmetadata")

    with Cluster("Event fan-out"):
        topic = SNS("SNS")
        queue = SQS("SQS")

    with Cluster("Process"):
        worker = EC2("EC2 worker\nCSV to Parquet")
        curated = S3("S3 - curated")

    with Cluster("Catalog & query"):
        trigger = Lambda("Crawler trigger")
        crawler = GlueCrawlers("Glue crawler")
        catalog = Glue("Glue catalog")
        athena = Athena("Athena")

    client >> Edge(label="POST /upload") >> api >> uploader
    uploader >> raw
    uploader >> meta
    raw >> Edge(label="ObjectCreated") >> topic >> queue >> worker
    worker >> curated >> trigger >> crawler >> catalog >> athena
