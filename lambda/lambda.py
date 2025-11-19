import gzip
import json
import base64
import urllib.request
import os

SPLUNK_URL = os.environ.get("SPLUNK_HEC_URL")
SPLUNK_TOKEN = os.environ.get("SPLUNK_HEC_TOKEN")

def send_to_splunk(event_payload):
    if not (SPLUNK_URL and SPLUNK_TOKEN):
        print("Splunk HEC settings not configured.")
        return

    data = json.dumps({"event": event_payload}).encode("utf-8") # Encodes data to splunk compatible data
    req = urllib.request.Request(SPLUNK_URL, data=data, method="POST") # HTTP POST request to splunk HEC
    req.add_header("Authorization", "Splunk " + SPLUNK_TOKEN)
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read()
            print("Splunk response:", resp.status, body)
    except Exception as e:
        print("Error sending to Splunk:", e)

def lambda_handler(event, context):
    cw_data = event.get("awslogs", {}). # Get Cloudwatch logs
    if not cw_data:
        print("No awslogs field.")
        return

    compressed = cw_data.get("data") # Get Encoded Data
    if not compressed:
        print("No data to decode.")
        return

    data = base64.b64decode(compressed). # Decode the data
    try:
        decompressed = gzip.decompress(data) # Decompress the data
    except Exception as e:
        print("Failed to decompress:", e)
        return

    payload = json.loads(decompressed) # Make data into json format
    for le in payload.get("logEvents", []):
        event_obj = {
            "message": le.get("message"),
            "timestamp": le.get("timestamp"),
            "logGroup": payload.get("logGroup"),
            "logStream": payload.get("logStream"),
            "id": le.get("id")
        }
        send_to_splunk(event_obj) # Call fn to send logs to splunk
    return {"status": "ok"}
