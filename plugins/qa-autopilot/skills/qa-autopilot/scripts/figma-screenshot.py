#!/usr/bin/env python3
"""Fetch the rendered PNG of a Figma node and save it as a design reference.

Usage:
    figma-screenshot.py <figma-url> <output-png-path> [--scale N]

Requires the FIGMA_TOKEN env var (a Figma personal access token with
file_content:read). On any failure it exits non-zero with a one-line reason on
stderr so the caller can fall back to asking the user for the screenshot.

Exit codes:
    0  saved
    2  no FIGMA_TOKEN
    3  url missing a node id (need a "Copy link to selection" link)
    4  figma rejected the request (bad token / no access / unknown node)
    5  figma returned no image for the node
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

IMAGES_ENDPOINT = "https://api.figma.com/v1/images"


def fail(exit_code, reason):
    print(reason, file=sys.stderr)
    sys.exit(exit_code)


def file_key_from(url):
    match = re.search(r"/(?:file|design|proto|board)/([A-Za-z0-9]+)", url)
    if not match:
        fail(3, f"Could not find a Figma file key in: {url}")
    return match.group(1)


def node_id_from(url):
    query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
    raw = (query.get("node-id") or query.get("node_id") or [None])[0]
    if not raw:
        fail(3, "URL has no node-id. In Figma: right-click the frame > "
                "Copy link to selection, then pass that link.")
    return raw.replace("-", ":")


def request_render_url(file_key, node_id, scale, token):
    params = urllib.parse.urlencode({"ids": node_id, "format": "png", "scale": scale})
    request = urllib.request.Request(
        f"{IMAGES_ENDPOINT}/{file_key}?{params}",
        headers={"X-Figma-Token": token},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        fail(4, f"Figma API {error.code}: {error.reason} "
                "(check FIGMA_TOKEN, file access, and the node id).")
    except urllib.error.URLError as error:
        fail(4, f"Could not reach Figma API: {error.reason}")

    if payload.get("err"):
        fail(4, f"Figma API error: {payload['err']}")
    render_url = (payload.get("images") or {}).get(node_id)
    if not render_url:
        fail(5, f"Figma returned no image for node {node_id}.")
    return render_url


def download(render_url, output_path):
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with urllib.request.urlopen(render_url, timeout=60) as source, \
            open(output_path, "wb") as target:
        target.write(source.read())


def parse_args():
    parser = argparse.ArgumentParser(description="Save a Figma node render as a PNG reference.")
    parser.add_argument("url", help="Figma link to the frame/node")
    parser.add_argument("output", help="Where to write the PNG")
    parser.add_argument("--scale", default="2", help="Render scale (default 2)")
    return parser.parse_args()


def main():
    args = parse_args()
    token = os.environ.get("FIGMA_TOKEN")
    if not token:
        fail(2, "FIGMA_TOKEN is not set. Create a token at "
                "https://www.figma.com/developers/api#access-tokens and "
                "`export FIGMA_TOKEN=figd_...`, or provide the screenshot manually.")

    render_url = request_render_url(file_key_from(args.url), node_id_from(args.url), args.scale, token)
    download(render_url, args.output)
    print(args.output)


if __name__ == "__main__":
    main()
