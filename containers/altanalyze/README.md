# AltAnalyze Docker Container

This directory contains Docker build files for creating a containerized version of AltAnalyze for alternative splicing analysis from RNA-seq data.

## Overview

The Docker container provides a complete, reproducible environment for AltAnalyze with all dependencies pre-installed:

- **AltAnalyze**: Latest version from GitHub
- **Python 3**: With scientific computing libraries (NumPy, SciPy, Pandas, etc.)
- **GNU Parallel**: For multi-core BAM processing
- **Enhanced Script**: Improved AltAnalyze.sh with better error handling and logging

## Quick Start

### Building the Container

```bash
# Build the Docker image (multi-arch)
cd AltAnalyze_2/
bash docker_build.sh --tag v1.5.3

# Or build manually
docker buildx build --platform linux/amd64,linux/arm64 -t ndeeseee/altanalyze:latest .
```

### Running the Container

```bash
# Basic usage - show help
docker run --rm ndeeseee/altanalyze:latest --help

# BAM to BED conversion
docker run --rm -v /path/to/data:/mnt \
  ndeeseee/altanalyze:latest \
  bam_to_bed bam/sample.bam

# BED to junction analysis
docker run --rm -v /path/to/data:/mnt \
  ndeeseee/altanalyze:latest \
  bed_to_junction bed_folder

# Full pipeline with parallelization
docker run --rm -v /path/to/data:/mnt \
  ndeeseee/altanalyze:latest \
  identify bam_folder 4
```

## Container Architecture

### Multi-Stage Build

The Dockerfile uses a multi-stage build approach:

1. **Builder Stage**: Downloads AltAnalyze and installs build dependencies
2. **Runtime Stage**: Creates minimal production image with only runtime dependencies

### Security Features

- **Non-root user**: Container runs as `altanalyze` user (not root)
- **Minimal base**: Ubuntu 22.04 LTS with only essential packages
- **Health checks**: Validates Python and AltAnalyze installation

### Cross-Platform Support

- **Architecture**: Built for x86_64 (can be adapted for ARM64)
- **OS Support**: Works on Linux, macOS, and Windows with Docker
- **Cloud Ready**: Compatible with Terra, Cromwell, and other WDL engines

## Analysis Modes

The container supports all AltAnalyze analysis modes:

### 1. BAM to BED (`bam_to_bed`)

Convert BAM files to BED format for junction and exon analysis.

```bash
docker run --rm -v $(pwd):/mnt \
  ndeeseee/altanalyze:latest \
  bam_to_bed bam/sample.bam
```

**Outputs:**
- `sample.bed`: Exon-level BED file
- `sample__junction.bed`: Junction-level BED file

### 2. BED to Junction Analysis (`bed_to_junction`)

Analyze alternative splicing from BED files.

```bash
docker run --rm -v $(pwd):/mnt \
  ndeeseee/altanalyze:latest \
  bed_to_junction bed_folder
```

**Outputs:**
- `altanalyze_output/`: Complete AltAnalyze results
- Junction count matrices and PSI values

### 3. Full Pipeline (`identify`)

Complete pipeline: BAM → BED → junction analysis with parallelization.

```bash
docker run --rm -v $(pwd):/mnt \
  frankligy123/altanalyze:latest \
  identify bam_folder 4
```

**Parameters:**
- `bam_folder`: Directory containing BAM files
- `4`: Number of CPU cores for parallel processing

### 4. Differential Expression (`DE`)

Perform differential expression analysis on AltAnalyze results.

```bash
docker run --rm -v $(pwd):/mnt \
  frankligy123/altanalyze:latest \
  DE altanalyze_output groups.txt
```

### 5. Gene Ontology (`GO`)

Gene ontology enrichment analysis.

```bash
docker run --rm -v $(pwd):/mnt \
  frankligy123/altanalyze:latest \
  GO gene_list.txt
```

### 6. Differential Alternative Splicing (`DAS`)

Identify differentially spliced events.

```bash
docker run --rm -v $(pwd):/mnt \
  frankligy123/altanalyze:latest \
  DAS altanalyze_output groups.txt
```

## Configuration

### Environment Variables

The container supports several environment variables for customization:

```bash
docker run --rm -v $(pwd):/mnt \
  -e SPECIES=Mm \
  -e PLATFORM=RNASeq \
  -e VERSION=EnsMart91 \
  ndeeseee/altanalyze:latest \
  bam_to_bed bam/mouse_sample.bam
```

**Available Variables:**
- `SPECIES`: Species code (default: `Hs` for human)
  - `Hs`: Human
  - `Mm`: Mouse
  - `Rn`: Rat
  - `Dr`: Zebrafish
- `PLATFORM`: Analysis platform (default: `RNASeq`)
- `VERSION`: Ensembl database version (default: `EnsMart91`)
- `PYTHON_CMD`: Python command (default: `python3`)

### Volume Mounts

Mount your data directory to `/mnt` in the container:

```bash
# Mount current directory
docker run --rm -v $(pwd):/mnt ndeeseee/altanalyze:latest <command>

# Mount specific directory
docker run --rm -v /path/to/data:/mnt ndeeseee/altanalyze:latest <command>

# Mount with read-only option
docker run --rm -v /path/to/data:/mnt:ro ndeeseee/altanalyze:latest <command>
```

## Integration with WDL

This container is designed to work with the `workflows/splicing_analysis.wdl` workflow:

```wdl
runtime {
    docker: "ndeeseee/altanalyze:latest"
    cpu: cpu_cores
    memory: "64 GB"
    disks: "local-disk 100 HDD"
}
```

The workflow uses this container for:
- BAM to BED conversion (scattered across samples)
- BED to junction analysis (single task on all BED files)

## Development

### Building Custom Images

To build with a custom tag:

```bash
bash docker_build.sh --tag v1.5.3
```

### Testing

The build script includes comprehensive tests:

```bash
# Run all tests
bash docker_build.sh

# Skip build, only test
bash docker_build.sh --skip-build

# Skip tests, only build
bash docker_build.sh --skip-test
```

### Customization

To customize the container:

1. **Add dependencies**: Modify the `RUN apt-get install` commands in Dockerfile
2. **Change AltAnalyze version**: Update the download URL in Dockerfile
3. **Modify scripts**: Edit `AltAnalyze.sh` for custom analysis logic
4. **Update base image**: Change `FROM ubuntu:22.04` to different base

## Troubleshooting

### Common Issues

1. **Permission denied**: Ensure volume mounts have correct permissions
   ```bash
   chmod -R 755 /path/to/data
   ```

2. **Out of memory**: Increase Docker memory limit or reduce analysis scope

3. **Missing files**: Check that input files are in the mounted volume path

4. **Species not supported**: Verify species code and ensure AltAnalyze database exists

### Debug Mode

Run container interactively for debugging:

```bash
docker run -it --rm -v $(pwd):/mnt \
  --entrypoint /bin/bash \
  ndeeseee/altanalyze:latest
```

### Logs

Container provides detailed logging:

```bash
# View logs with timestamps
docker run --rm -v $(pwd):/mnt \
  ndeeseee/altanalyze:latest \
  identify bam_folder 4 2>&1 | grep -E '\[(INFO|ERROR|WARN)\]'
```

## Performance

### Resource Requirements

- **CPU**: 1-16 cores (parallelization supported)
- **Memory**: 4-64 GB (depends on dataset size)
- **Disk**: 10-100 GB (temporary files and outputs)

### Optimization Tips

1. **Use parallel mode**: `identify` mode with multiple cores
2. **SSD storage**: Fast I/O improves performance
3. **Memory allocation**: Match Docker memory to analysis requirements
4. **Batch processing**: Process multiple samples together

## Support

- **Documentation**: [AltAnalyze Manual](http://altanalyze.readthedocs.io/)
- **Issues**: [GitHub Issues](https://github.com/NDeeSeee/altanalyze2_snaf/issues)
- **WDL Workflows**: Use `workflows/splicing_analysis.wdl`

## License

This Docker container setup is provided under the same license as the AltAnalyze project. See project LICENSE file for details.