# Sample Test Data

This directory contains a sample of the full test dataset collected from the Cilium vs Packetbeat comparison.

## Sample Size

Each file contains the **first 5000 events/flows** from the original dataset.

## Original Dataset

- **Hubble flows:** 12,232 total flows
- **Packetbeat events:** 970,539 total events
- **Total size:** ~4 GB
- **Sample size:** 16M

## Files Included

### Hubble Data (`hubble/`)
- cilium-status.txt (2.3K)
- hubble-flows-all.json (6.4M)
- hubble-flows-demo.json (429K)
- hubble-flows-dns.json (482)
- hubble-flows-dropped.json (59K)
- hubble-flows-http.json (482)
- hubble-stats.txt (179)

### Packetbeat Data (`packetbeat/`)
- packetbeat-combined.json (8.8M)
- packetbeat-stats.txt (23K)

### Metadata
- `metrics/` - Resource usage snapshots
- `cluster/` - Cluster state information

## Using This Sample Data

### Quick Analysis

View HTTP status codes (Hubble):
```bash
cat hubble/hubble-flows-http.json | jq -r '.l7.http.code' | sort | uniq -c
```

View HTTP status codes (Packetbeat):
```bash
cat packetbeat/packetbeat-combined.json | jq -r 'select(.type=="http") | .http.response.status_code' | sort | uniq -c
```

View policy violations (Hubble):
```bash
cat hubble/hubble-flows-dropped.json | jq -r '.drop_reason_desc' | sort | uniq -c
```

### Running Analysis Scripts

The analysis scripts in `testing/` and `analysis/` will work with this sample data, though results will be based on only 5000 events instead of the full dataset.

## Regenerating Sample Data

To create a sample with a different size:

```bash
# Create sample with 500 events
./create-sample-data.sh 500

# Create sample with 5000 events
./create-sample-data.sh 5000
```

## Full Dataset

The complete 4 GB dataset is available:
- Via GitHub Releases (if uploaded)
- On request from repository owner
- By re-running the test: `./testing/deploy-error-scenarios.sh`

## Sample Limitations

This sample represents only **0.5%** of the Packetbeat events and **40.9%** of the Hubble flows. 

Patterns and statistics derived from this sample may not be representative of the full dataset, but the sample is sufficient for:
- Understanding data formats
- Testing analysis scripts
- Demonstrating tool capabilities
- Learning the workflow

For production decisions, analysis should be performed on complete datasets from your own environment.

---

**Sample generated:** Thu 16 Apr 11:51:43 BST 2026  
**Test date:** February 5, 2026  
**Script:** `create-sample-data.sh 5000`
