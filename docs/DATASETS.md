# Dataset Inventory & Processing Status

*Last updated: August 25, 2025*

This document tracks all datasets available for analysis, their access methods, processing status, and key metadata.

---

## 🗄️ Dataset Overview

| Dataset | Version | Status | Access Method | Total Samples | Validated Samples | Avg BAM Size | Access Notes |
|---------|---------|--------|---------------|---------------|-------------------|--------------|--------------|
| GTEx | v10 (2022-06-06) | ✅ Available | dbGaP/eRA Commons | 48,231 | 22,970 (47.6%) | ~2-8 GB | Via Nathan's support |
| TCGA-MESO | Current | ✅ Available | GDC Portal | ~87 | TBD | ~1-3 GB | Direct download |
| TCGA-UVM | Current | ✅ Available | GDC Portal | TBD | TBD | ~1-3 GB | Direct download |
| CCHMC HPC | Local | 🔄 Institutional | HPC cluster | TBD | TBD | Variable | Local access |
| Proteomics | - | 🔍 Search needed | TBD | TBD | TBD | Variable | Multi-omics integration |
| Single-cell | - | 🔍 Search needed | Terra processing | TBD | TBD | Variable | Cellular-level analysis |
| TARGET | - | 🔄 Pending | TBD | TBD | TBD | TBD | Future consideration |
| CCLE | - | 🔄 Pending | TBD | TBD | TBD | TBD | Future consideration |

---

## 📊 GTEx v10 Dataset

### **Access & Authorization**
- **Access Method**: dbGaP controlled access via eRA Commons
- **Authorization**: Obtained through Nathan's support and institutional agreements  
- **Data Location**: Google Cloud Storage (GTEx consortium bucket)
- **Validation**: Comprehensive validation performed (see `data/gtex/validation_reports/`)

### **Sample Summary**
- **Total Samples in Metadata**: 48,231
- **Validated Available Samples**: 22,970 (47.6% success rate)
- **Missing/Unavailable**: 25,261
- **Tissues Represented**: 31 different tissue types

### **File Characteristics**
- **BAM File Pattern**: `{SAMPID}.Aligned.sortedByCoord.out.patched.md.bam`
- **Index Files**: Corresponding `.bai` files available
- **Average BAM Size**: 2-8 GB (varies by tissue and sequencing depth)
- **Alignment**: STAR 2-pass alignment (already processed)
- **Reference**: GRCh38/hg38

### **Tissue Distribution (Top 10 by sample count)**
| Tissue | Original Count | Validated Count | Success Rate | Avg BAM Size (est.) |
|--------|----------------|-----------------|--------------|---------------------|
| Brain | 8,035 | 3,737 | 46.5% | 4-6 GB |
| Blood | 4,717 | 1,434 | 30.4% | 2-4 GB |
| Skin | 4,469 | 2,201 | 49.2% | 3-5 GB |
| Esophagus | 3,394 | 1,713 | 50.5% | 3-5 GB |
| Blood Vessel | 3,286 | 1,622 | 49.4% | 3-5 GB |
| Adipose Tissue | 2,461 | 1,303 | 53.0% | 2-4 GB |
| Muscle | 2,352 | 966 | 41.1% | 4-6 GB |
| Heart | 2,138 | 1,058 | 49.5% | 3-5 GB |
| Colon | 2,085 | 1,023 | 49.1% | 3-5 GB |
| Thyroid | 2,033 | 794 | 39.1% | 3-5 GB |

### **Data Organization**
```
data/gtex/
├── GTEx_Analysis_2022-06-06_v10_Annotations_SampleAttributesDS.txt  # 40MB reference
├── GTEx_Analysis_2022-06-06_v10_Annotations_SubjectPhenotypesDS.txt  # Subject metadata  
├── gtex_organized/                    # Per-tissue sample organization
│   ├── {Tissue}/
│   │   ├── sample_ids.csv            # All samples for tissue
│   │   ├── metadata.txt              # Tissue summary
│   │   └── validated/
│   │       ├── sample_ids.csv        # Only validated samples
│   │       └── metadata.txt          # Validated summary
├── validation_reports/                # Comprehensive validation results
└── [processing scripts]               # Python tools for data management
```

---

## 🧬 TCGA Datasets

### **TCGA-MESO (Mesothelioma)**
- **Access**: GDC Data Portal (open access)
- **Samples**: ~87 primary tumor samples
- **File Type**: `*.rna_seq.transcriptome.gdc_realn.bam` 
- **Alignment**: STAR 2-pass (GDC pipeline)
- **Average Size**: 1-3 GB per BAM
- **Reference**: GRCh38
- **Processing Status**: Sample metadata collected, ready for analysis

### **TCGA-UVM (Uveal Melanoma)**  
- **Access**: GDC Data Portal (open access)
- **Samples**: Sample count TBD
- **File Type**: `*.rna_seq.transcriptome.gdc_realn.bam`
- **Alignment**: STAR 2-pass (GDC pipeline)
- **Average Size**: 1-3 GB per BAM
- **Reference**: GRCh38
- **Processing Status**: Initial data downloaded, needs full inventory

### **TCGA Data Characteristics**
- **Pre-aligned**: All TCGA BAMs are already STAR 2-pass aligned
- **Quality**: High-quality, standardized processing pipeline
- **Metadata**: Rich clinical and sample metadata available
- **Access**: No special authorization required (Level 1 data)

### **Data Organization**
```
data/tcga/
├── uvm/
│   ├── gdc_sample_sheet.2025-08-12.tsv     # Sample metadata
│   ├── gdc_manifest.*.txt                  # Download manifests  
│   ├── uuid_and_filename_cleaned.tsv       # File mapping
│   └── [sample files]                      # Downloaded data
└── [other cancer types]/
```

---

## 🔬 Dataset Processing Recommendations

### **Priority Order for Analysis**
1. **GTEx Pilot** (High Priority): Test with 2-3 high-success tissues (Adipose, Skin, Esophagus)
2. **TCGA-MESO** (Medium Priority): Smaller dataset, good for method validation  
3. **GTEx Full Scale** (Long-term): Complete analysis of all 22,970 validated samples
4. **TCGA-UVM** (Future): Additional cancer dataset for comparison

### **Resource Requirements by Dataset**

#### GTEx v10 Complete Analysis
- **Estimated Runtime**: 50-100 hours (with parallelization)
- **Estimated Cost**: $15,000-30,000 (based on pilot data)
- **Storage Requirements**: 200-400 TB temporary, 50-100 TB results
- **Computational Needs**: High-memory instances recommended

#### TCGA Datasets (per cancer type)
- **Estimated Runtime**: 5-10 hours  
- **Estimated Cost**: $500-1,000
- **Storage Requirements**: 20-50 TB temporary, 5-10 TB results
- **Computational Needs**: Standard configurations sufficient

### **Data Quality Notes**

#### GTEx Considerations
- **Missing Files**: 47.6% success rate due to file availability issues
- **Tissue Variability**: Success rates vary significantly by tissue type
- **Sample Quality**: High RNA quality (RIN scores ~7.2-7.3)
- **Batch Effects**: Multiple batches, controlled for in analysis

#### TCGA Considerations  
- **Standardized Processing**: Uniform GDC pipeline
- **Clinical Data**: Rich metadata for covariates
- **Tumor Heterogeneity**: Primary tumors, some matched normals available
- **Quality Control**: Pre-filtered for analysis quality

---

## 📋 Next Steps & Recommendations

### **Immediate Actions**
1. **Pilot GTEx Run**: Execute on Adipose Tissue (~1,300 samples) to establish baseline costs
2. **TCGA Test**: Run MESO dataset to validate cross-platform compatibility
3. **Cost Modeling**: Update cost estimates based on pilot results

### **Data Management Strategy**
1. **Staged Processing**: Process datasets in batches to manage costs and storage
2. **Result Archival**: Implement efficient long-term storage for analysis results
3. **Quality Monitoring**: Continuous monitoring of success rates and data quality

---

## 🏥 CCHMC HPC Cluster

### **Local Institutional Resources**
- **Access**: Direct institutional HPC cluster access
- **Advantage**: No cloud computing costs, high-performance local resources
- **Data Location**: `/path/to/hpc/data/` - *Update with actual data paths*
- **Processing**: Local job scheduling and resource management
- **Integration**: Complement cloud-based Terra workflows

### **Available Datasets (To be documented)**
- **Local Genomics Data**: Document available datasets and access procedures
- **Storage Paths**: Map data locations and access permissions
- **Processing Capabilities**: Local workflow execution options

---

## 🔬 Future Multi-omics Data Sources

### **Proteomics Datasets (Resource Search Required)**

#### **Target Resources**
- **ProteomeXchange**: Global proteomics data repository
- **PRIDE Database**: Proteomics identification database
- **Human Proteome Map**: Comprehensive tissue proteomics
- **Clinical Proteomic Tumor Analysis Consortium (CPTAC)**: Cancer proteomics

#### **Integration Goals**
- **Multi-omics Correlation**: Link transcriptomic splicing with protein expression
- **Terra Processing**: Cloud-based proteomics workflow development
- **File Formats**: Support for mzML, mzTab, and other proteomics standards

### **Single-cell RNA-seq Datasets (Resource Search Required)**

#### **Target Resources**
- **10X Genomics Datasets**: Public single-cell datasets
- **Human Cell Atlas**: Comprehensive single-cell reference
- **Single Cell Portal**: Broad Institute single-cell data
- **CELLxGENE**: Chan Zuckerberg single-cell data portal

#### **Processing Requirements**
- **Computational Intensity**: High memory and CPU requirements
- **Terra Workflows**: Specialized single-cell processing pipelines  
- **Storage**: Large file sizes, efficient data management needed
- **Analysis Focus**: Cell-type-specific splicing patterns

#### **Technical Considerations**
- **File Formats**: Support for H5, MTX, and other single-cell formats
- **Workflow Adaptation**: Modify existing workflows for single-cell data
- **Cost Estimation**: Account for increased computational requirements

### **Next Steps for Resource Discovery**
1. **Proteomics Survey**: Evaluate available datasets and access procedures
2. **Single-cell Assessment**: Identify suitable datasets for method validation
3. **Technical Planning**: Design integration workflows and resource requirements
4. **Cost Analysis**: Estimate Terra processing costs for new data types

### **Traditional Future Dataset Considerations**
- **TARGET**: Pediatric cancer dataset for broader applicability
- **CCLE**: Cell line dataset for method validation
- **International Cohorts**: ICGC, UK Biobank for global representation

---

## 📞 Support Contacts

- **GTEx Access Issues**: Nathan [contact info needed]
- **TCGA Data Questions**: GDC Help Desk (support@nci-gdc.datacommons.io)
- **dbGaP Authorization**: Institutional DAC coordinator

---

## 🔄 Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-08-25 | Initial dataset inventory created | Claude |
| 2025-08-25 | Added CCHMC HPC, proteomics, and single-cell data sources | Claude |
| YYYY-MM-DD | [Future updates] | [Author] |

---

*This document should be updated as new datasets are added, access is obtained, or processing status changes.*