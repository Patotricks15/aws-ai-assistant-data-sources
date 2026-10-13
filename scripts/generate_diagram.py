"""Generates docs/architecture.drawio for the AI Assistant with Data Sources
project using drawpyo.

Run with: python3 scripts/generate_diagram.py
"""
import os

import drawpyo

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")

AWS4_BASE = (
    "sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;"
    "dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;"
    "fontSize=11;fontStyle=0;aspect=fixed;pointerEvents=1;"
)

# Non-AWS / unconfirmed-stencil style, used for FSx (no confirmed resIcon) and
# for the generic third-party enterprise connector, which isn't an AWS service.
GENERIC_STYLE = (
    "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFF2CC;strokeColor=#D6B656;"
    "fontSize=10;fontColor=#7F6000;align=center;"
)


def aws_style(icon_name, fill_color):
    return (
        f"{AWS4_BASE}fillColor={fill_color};shape=mxgraph.aws4.resourceIcon;"
        f"resIcon=mxgraph.aws4.{icon_name};"
    )


def add_node(page, name, x, y, icon_name, fill_color, width=64, height=64):
    node = drawpyo.diagram.Object(page=page, value=name)
    node.position = (x, y)
    node.geometry.width = width
    node.geometry.height = height
    node.apply_style_string(aws_style(icon_name, fill_color))
    return node


def add_generic_node(page, name, x, y, width=110, height=64):
    """Node for data sources with no confirmed AWS4 resIcon (FSx) or that
    aren't an AWS service at all (third-party connector)."""
    node = drawpyo.diagram.Object(page=page, value=name)
    node.position = (x, y)
    node.geometry.width = width
    node.geometry.height = height
    node.apply_style_string(GENERIC_STYLE)
    return node


def add_boundary_group(page, name, x, y, width, height, color="#232F3E"):
    group = drawpyo.diagram.Object(page=page, value=name)
    group.position = (x, y)
    group.geometry.width = width
    group.geometry.height = height
    group.apply_style_string(
        "shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_security_group;"
        f"strokeColor={color};fillColor=none;verticalAlign=top;align=left;"
        f"spacingLeft=30;fontColor={color};dashed=1;"
    )
    return group


def add_plain_group(page, name, x, y, width, height):
    group = drawpyo.diagram.Object(page=page, value=name)
    group.position = (x, y)
    group.geometry.width = width
    group.geometry.height = height
    group.apply_style_string(
        "rounded=0;whiteSpace=wrap;html=1;dashed=1;dashPattern=8 4;fillColor=none;"
        "strokeColor=#7AA116;verticalAlign=top;align=center;fontColor=#7AA116;fontSize=11;"
    )
    return group


def add_edge(page, source, target, label=None, bidirectional=False):
    edge = drawpyo.diagram.Edge(page=page, source=source, target=target, label=label)
    edge.waypoints = "orthogonal"
    edge.endArrow = "block"
    edge.startArrow = "block" if bidirectional else "none"
    edge.strokeColor = "#545B64"
    return edge


def build_diagram():
    file = drawpyo.File()
    file.file_name = "architecture.drawio"
    file.file_path = OUTPUT_DIR

    page = drawpyo.Page(file=file)
    page.name = "AI Assistant with Data Sources"

    user = add_node(page, "User", 20, 260, "client", "#232F3E")

    aws_cloud = add_boundary_group(page, "AWS Cloud", 160, 40, 900, 560)

    ai_assistant = add_node(page, "AI assistant", 220, 260, "machine_learning", "#01A88D")

    access_management = add_node(
        page, "Manage access and\nsingle sign-on", 220, 100,
        "identity_and_access_management_iam", "#DD344C",
    )

    # "Data sources" group box, nested inside the AWS Cloud boundary, with the
    # three data-source icons placed side by side.
    data_sources_group = add_plain_group(page, "Data sources", 460, 140, 520, 340)

    document_bucket = add_node(page, "Document\nbucket (S3)", 500, 300, "bucket", "#7AA116")
    # No confirmed AWS4 resIcon for FSx -- generic placeholder per the skill notes.
    fsx_docs = add_generic_node(page, "FSx: complex\nmachinery & process\ndocumentation", 660, 290)
    third_party = add_generic_node(page, "Third-party enterprise\napps / document\nrepositories connector", 840, 290)

    add_edge(page, user, ai_assistant, "Query", bidirectional=True)
    add_edge(page, ai_assistant, access_management, "Get user & group info")
    add_edge(page, access_management, ai_assistant, "Permissions")

    add_edge(page, ai_assistant, document_bucket, "Ingest / search", bidirectional=True)
    add_edge(page, ai_assistant, fsx_docs, "Ingest / search", bidirectional=True)
    add_edge(page, ai_assistant, third_party, "Ingest / search", bidirectional=True)

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    file.write()
    print(f"Wrote {os.path.join(OUTPUT_DIR, file.file_name)}")


if __name__ == "__main__":
    build_diagram()
