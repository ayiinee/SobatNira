"""Build the synthetic flow with Langflow 1.13.3 in its isolated environment."""
import argparse
import json
from pathlib import Path

from lfx.components.input_output import ChatOutput
from lfx.graph import Graph

from production_insight_component import ProductionInsight


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    target = parser.parse_args().output
    source = ProductionInsight()
    sink = ChatOutput().set(input_value=source.insight, should_store_message=False)
    flow = Graph(source, sink).dump(name="SobatNira Production Insight")
    nodes, edges = flow["data"]["nodes"], flow["data"]["edges"]
    if len(nodes) != 2 or len(edges) != 1:
        raise ValueError("Flow POC memerlukan satu edge dari gateway ke Chat Output.")
    node = next(entry["data"]["node"] for entry in nodes if entry["id"] == source.get_id())
    code = Path(__file__).with_name("production_insight_component.py")
    node["template"]["code"]["value"] = code.read_text(encoding="utf-8")
    target.write_text(json.dumps(flow, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
