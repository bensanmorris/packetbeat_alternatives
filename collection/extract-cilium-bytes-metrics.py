#!/usr/bin/env python3
"""
Cilium Byte Metrics Extractor

Parses Cilium Prometheus metrics and extracts byte/packet counters per pod.
Converts raw Prometheus text format to structured JSON.

Usage:
    python3 extract-cilium-byte-metrics.py <input-file> <output-file>
    
    Or pipe from stdin:
    curl http://localhost:9965/metrics | python3 extract-cilium-byte-metrics.py - cilium-byte-metrics.json

Input:  Raw Prometheus metrics (text format)
Output: JSON file with byte/packet counters per pod

Example output:
{
  "demo/frontend-abc123": {
    "egress_bytes": 1234567,
    "ingress_bytes": 987654,
    "total_bytes": 2222221,
    "egress_packets": 1234,
    "ingress_packets": 987,
    "total_packets": 2221
  }
}
"""

import re
import json
import sys


def parse_prometheus_metrics(metrics_text):
    """
    Parse Prometheus metrics text and extract Cilium endpoint byte/packet counters.
    
    Args:
        metrics_text: Raw Prometheus metrics as string
        
    Returns:
        Dictionary mapping "namespace/pod" to metrics dict
    """
    metrics = {}
    
    for line in metrics_text.split('\n'):
        # Skip comments and empty lines
        if line.startswith('#') or not line.strip():
            continue
        
        # Parse endpoint byte metrics
        # Format: cilium_endpoint_egress_bytes_total{endpoint_id="123",namespace="demo",pod="frontend-abc"} 12345
        
        # Egress bytes
        match = re.match(
            r'cilium_endpoint_egress_bytes_total\{[^}]*namespace="([^"]+)"[^}]*pod="([^"]+)"[^}]*\}\s+(\d+)',
            line
        )
        if match:
            namespace, pod, bytes_val = match.groups()
            key = f"{namespace}/{pod}"
            if key not in metrics:
                metrics[key] = {}
            metrics[key]['egress_bytes'] = int(bytes_val)
        
        # Ingress bytes
        match = re.match(
            r'cilium_endpoint_ingress_bytes_total\{[^}]*namespace="([^"]+)"[^}]*pod="([^"]+)"[^}]*\}\s+(\d+)',
            line
        )
        if match:
            namespace, pod, bytes_val = match.groups()
            key = f"{namespace}/{pod}"
            if key not in metrics:
                metrics[key] = {}
            metrics[key]['ingress_bytes'] = int(bytes_val)
        
        # Egress packets
        match = re.match(
            r'cilium_endpoint_egress_packets_total\{[^}]*namespace="([^"]+)"[^}]*pod="([^"]+)"[^}]*\}\s+(\d+)',
            line
        )
        if match:
            namespace, pod, packets_val = match.groups()
            key = f"{namespace}/{pod}"
            if key not in metrics:
                metrics[key] = {}
            metrics[key]['egress_packets'] = int(packets_val)
        
        # Ingress packets
        match = re.match(
            r'cilium_endpoint_ingress_packets_total\{[^}]*namespace="([^"]+)"[^}]*pod="([^"]+)"[^}]*\}\s+(\d+)',
            line
        )
        if match:
            namespace, pod, packets_val = match.groups()
            key = f"{namespace}/{pod}"
            if key not in metrics:
                metrics[key] = {}
            metrics[key]['ingress_packets'] = int(packets_val)
    
    # Calculate totals for each pod
    for key in metrics:
        metrics[key]['total_bytes'] = (
            metrics[key].get('egress_bytes', 0) + 
            metrics[key].get('ingress_bytes', 0)
        )
        metrics[key]['total_packets'] = (
            metrics[key].get('egress_packets', 0) + 
            metrics[key].get('ingress_packets', 0)
        )
    
    return metrics


def main():
    """Main entry point."""
    # Parse command line arguments
    if len(sys.argv) < 2:
        print(__doc__)
        print("\nError: Input file required", file=sys.stderr)
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    # Read input
    try:
        if input_file == '-':
            # Read from stdin
            metrics_text = sys.stdin.read()
        else:
            # Read from file
            with open(input_file, 'r') as f:
                metrics_text = f.read()
    except IOError as e:
        print(f"Error reading input: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Parse metrics
    try:
        metrics = parse_prometheus_metrics(metrics_text)
    except Exception as e:
        print(f"Error parsing metrics: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Output JSON
    output_json = json.dumps(metrics, indent=2, sort_keys=True)
    
    if output_file:
        # Write to file
        try:
            with open(output_file, 'w') as f:
                f.write(output_json)
            print(f"Metrics extracted: {len(metrics)} pods", file=sys.stderr)
            print(f"Output written to: {output_file}", file=sys.stderr)
        except IOError as e:
            print(f"Error writing output: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        # Write to stdout
        print(output_json)
    
    # Print summary to stderr
    if metrics:
        total_bytes = sum(m.get('total_bytes', 0) for m in metrics.values())
        total_packets = sum(m.get('total_packets', 0) for m in metrics.values())
        print(f"Total bytes across all pods: {total_bytes:,} ({total_bytes / 1048576:.1f} MB)", file=sys.stderr)
        print(f"Total packets across all pods: {total_packets:,}", file=sys.stderr)


if __name__ == '__main__':
    main()
