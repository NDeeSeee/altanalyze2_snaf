# AltAnalyze2 SNAF Documentation

This directory contains comprehensive setup and usage documentation for running the AltAnalyze2 SNAF workflows on cloud platforms using Terra, Altocumulus, and related tools.

## Quick Start

For immediate setup, follow these documents in order:

1. **[SETUP.md](./SETUP.md)** - Complete setup guide (start here!)
2. **[AUTHENTICATION.md](./AUTHENTICATION.md)** - Detailed authentication setup
3. **[ALTOCUMULUS_GUIDE.md](./ALTOCUMULUS_GUIDE.md)** - Complete Alto command reference
4. **[FIRECLOUD_SETUP.md](./FIRECLOUD_SETUP.md)** - Terra/FireCloud configuration
5. **[REPOSITORY_HEALTH_CHECKLIST.md](./REPOSITORY_HEALTH_CHECKLIST.md)** - Repository maintenance guide

## Document Overview

### 📋 [SETUP.md](./SETUP.md)
**Main setup guide covering everything needed to get started**
- Prerequisites and installation steps
- Google Cloud SDK setup
- Altocumulus installation  
- Authentication configuration
- Example workflow runs
- Troubleshooting guide

### 🔐 [AUTHENTICATION.md](./AUTHENTICATION.md)
**Comprehensive authentication and security guide**
- Google Cloud authentication (`gcloud auth login`, `gcloud auth application-default login`)
- Service account setup for automation
- Terra account configuration
- Security best practices
- Credential troubleshooting

### ⚡ [ALTOCUMULUS_GUIDE.md](./ALTOCUMULUS_GUIDE.md)
**Complete Altocumulus (alto) command reference**
- Installation and verification
- Terra commands (`alto terra run`, `alto terra add_method`)
- Cromwell commands (`alto cromwell run`, `alto cromwell list_jobs`)
- Advanced usage patterns
- Batch processing examples
- Error handling

### ☁️ [FIRECLOUD_SETUP.md](./FIRECLOUD_SETUP.md)
**Terra/FireCloud platform configuration**
- Terra workspace setup
- Billing configuration
- Method management
- Resource optimization
- Cost monitoring
- Security and compliance

### 🔍 [REPOSITORY_HEALTH_CHECKLIST.md](./REPOSITORY_HEALTH_CHECKLIST.md)
**Comprehensive repository maintenance and auditing guide**
- Emergency triage for problematic repositories
- Git hygiene and cleanup procedures
- Technology contamination detection
- Configuration validation
- Repository purpose alignment
- Health scoring and maintenance tips

## Project Management

### 📊 [PROJECT_STATUS.md](./PROJECT_STATUS.md)
**Project progress tracking and cost analysis**
- Current project milestones and progress
- Terra workflow execution results and costs
- Cost estimation models for scaling
- Performance benchmarks and optimization notes
- Future directions and planning
- Execution checklists and best practices

### 🗄️ [DATASETS.md](./DATASETS.md)
**Comprehensive dataset inventory and processing status**
- GTEx v10 dataset access and validation (22,970 validated samples)
- TCGA datasets (MESO, UVM) with metadata and processing notes
- Dataset characteristics, file sizes, and resource requirements
- Access methods, authorization status, and data organization
- Processing recommendations and priority analysis

## Workflow Documentation

For workflow-specific information, see the main repository documentation:
- **[Main README](../README.md)** - Workflow descriptions and usage
- **[Splicing Analysis](../workflows/splicing_analysis/)** - Input formats and examples
- **[STAR Alignment](../workflows/star_alignment/)** - STAR-specific configuration

## Setup Checklist

Use this checklist to verify your setup:

### Prerequisites
- [ ] Python 3.7+ installed
- [ ] Google Cloud SDK installed (`gcloud --version`)
- [ ] Docker installed (for local testing)

### Google Cloud Setup
- [ ] Google Cloud SDK authenticated (`gcloud auth login`)
- [ ] Application default credentials set (`gcloud auth application-default login`)
- [ ] Default project configured (`gcloud config set project PROJECT_ID`)
- [ ] Required APIs enabled (genomics, storage, compute)

### Altocumulus Setup
- [ ] Alto installed (`pip install altocumulus`)
- [ ] Alto working (`alto --version`)
- [ ] FISS working (`fissfc --version`)
- [ ] Terra commands accessible (`alto terra --help`)

### Google Cloud Storage Setup
- [ ] gsutil working (`gsutil version`)
- [ ] gsutil authenticated (`gsutil ls`)
- [ ] Can list buckets (`gsutil ls gs://`)

### Terra Setup
- [ ] Terra account created at [terra.bio](https://terra.bio)
- [ ] Billing account linked
- [ ] Can list workspaces (`fissfc space_list`)
- [ ] Can list projects (`fissfc proj_list`)
- [ ] Storage estimate works (`alto terra storage_estimate --output test.tsv --access owner`)

### Workflow Testing
- [ ] Sample input JSON prepared
- [ ] Test workflow submission successful
- [ ] Can download results with gsutil
- [ ] Output files accessible

## Common Use Cases

### First Time Setup
1. Follow [SETUP.md](./SETUP.md) step by step
2. Create a Terra workspace  
3. Test with provided example inputs

### Production Usage
1. Review [FIRECLOUD_SETUP.md](./FIRECLOUD_SETUP.md) for resource optimization
2. Set up proper authentication (see [AUTHENTICATION.md](./AUTHENTICATION.md))
3. Monitor costs and usage

### Getting Unstuck
1. Check `gcloud auth list` and `alto --version` work
2. Verify Terra workspace exists and has billing enabled
3. Ensure input JSON files reference accessible data

## Getting Help

### Documentation Issues
- **File issues**: Use the repository issue tracker
- **Improvements**: Submit pull requests with documentation updates

### Technical Support
- **Alto/Altocumulus**: [GitHub Issues](https://github.com/lilab-bcb/altocumulus/issues)
- **Terra Support**: [support.terra.bio](https://support.terra.bio)
- **Google Cloud**: [Google Cloud Support](https://cloud.google.com/support)

### Community Resources
- **Terra Community Forum**: [support.terra.bio/hc/en-us/community/topics](https://support.terra.bio/hc/en-us/community/topics)
- **Cromwell Documentation**: [cromwell.readthedocs.io](https://cromwell.readthedocs.io)
- **WDL Specification**: [github.com/openwdl/wdl](https://github.com/openwdl/wdl)

## Contributing to Documentation

We welcome contributions to improve these guides:

### Quick Fixes
- Fix typos or broken links
- Update command examples
- Clarify confusing sections

### Major Updates
- Add new authentication methods
- Document additional use cases
- Expand troubleshooting sections

### Style Guidelines
- Use clear, step-by-step instructions
- Include working command examples
- Explain the "why" behind complex steps
- Test all commands before documenting

---

**Next Steps**: Start with [SETUP.md](./SETUP.md) for complete installation instructions.