from __future__ import print_function
import boto3
import json

print("Loading function")

def lambda_handler(event, context):
    operation = event["operation"]

    dynamo = None
    if "tableName" in event:
        dynamo = boto3.resource("dynamodb").Table(event["tableName"])

    operations = {
        "create": lambda x: dynamo.put_item(**x),
        "read":   lambda x: dynamo.get_item(**x),
        "update": lambda x: dynamo.update_item(**x),
        "delete": lambda x: dynamo.delete_item(**x),
        "list":   lambda x: dynamo.scan(**x),
        "echo":   lambda x: x,
        "ping":   lambda x: "pong",
    }

    if operation in operations:
        return operations[operation](event.get("payload", {}))

    raise ValueError('Unrecognized operation "{}"'.format(operation))