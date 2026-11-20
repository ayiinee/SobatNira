"""Dev-only Langflow component for a synthetic SobatNira fixture."""
import json
import os
from contextlib import closing
from http.client import HTTPConnection

from lfx.custom import Component
from lfx.io import Output
from lfx.schema import Message


class ProductionInsight(Component):
    display_name = "SobatNira Production Insight"
    description = "Reads the fixed synthetic fixture through the local capability gateway."
    name = "SobatNiraProductionInsight"
    inputs = []
    outputs = [Output(name="message", display_name="Insight", method="insight")]

    def insight(self) -> Message:
        with closing(HTTPConnection("127.0.0.1", 8765, timeout=10)) as connection:
            connection.request("GET", "/production-insight",
                               headers={"X-Poc-Secret": os.environ["SOBATNIRA_POC_GATEWAY_SECRET"]})
            response = connection.getresponse()
            if response.status != 200:
                raise ValueError(f"Capability gateway HTTP {response.status}")
            return Message(text=json.dumps(json.load(response), ensure_ascii=False))
