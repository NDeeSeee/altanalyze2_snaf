# Repository Health Checklist

A comprehensive guide for auditing and fixing repository issues in bioinformatics/workflow projects.

## 🚨 Emergency Triage (Check These First)

### **1. Git Status Check**
```bash
git status --porcelain | wc -l    # Should be 0 for clean repo
git status --porcelain | head -10 # What kind of issues?
```
**Red Flags:**
- \> 10 uncommitted changes (investigate why)
- Many deleted files (D prefix) - likely execution artifacts
- Large number of untracked files (?? prefix) - contamination

### **2. Repository Size Audit**  
```bash
du -sh * | sort -hr | head -10    # Find bloated directories
find . -name "*.git" -prune -o -size +10M -type f -print  # Large files
```
**Red Flags:**
- `data/` directory > 50MB (should be external)
- `node_modules/` in non-JS project (contamination)
- `*_outputs/`, `results/`, `cache/` directories (execution artifacts)

### **3. Language/Technology Contamination**
```bash
find . -name "package*.json" -o -name "node_modules" -o -name "*.lock" | head -5
find . -name "*.pyc" -o -name "__pycache__" | head -5
```
**Red Flags:**
- Node.js files in bioinformatics repo
- Multiple language artifacts without clear purpose
- IDE-specific files committed

## 📋 Comprehensive Health Check

### **Phase 1: Repository Structure Analysis**

#### **1.1 File Type Distribution**
```bash
find . -type f | grep -E '\.[^.]+$' | cut -d. -f2- | sort | uniq -c | sort -nr | head -20
```
**Healthy Pattern:** Dominant file types should match repo purpose (`.wdl`, `.json` for workflows)

#### **1.2 Directory Purpose Check**
```bash
ls -la | grep "^d"
du -sh */ | sort -hr
```
**Red Flags:**
- Multiple unrelated technology stacks
- Execution output directories (`call-*`, `shard-*`, `cromwell-*`)
- Large data directories (`data/`, `datasets/`, `input/`)

#### **1.3 Hidden Files Audit**
```bash
find . -name ".*" -type f | head -20
```
**Clean up:** `.DS_Store`, `.vscode/`, editor configs, cache files

### **Phase 2: Git Repository Hygiene**

#### **2.1 Git Tracking Issues**
```bash
git ls-files | wc -l              # How many files tracked?
git ls-files --others | head -10  # What's untracked?
git diff --name-status | head -10 # What's modified?
```

#### **2.2 Large Files in Git History**
```bash
git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | sed -n 's/^blob //p' | sort -k2nr | head -10
```

#### **2.3 .gitignore Effectiveness**
```bash
git check-ignore -v * */  # Test current ignore rules
git clean -n              # What would be cleaned?
```

### **Phase 3: Configuration Files Audit**

#### **3.1 JSON/Config File Validation**
```bash
find . -name "*.json" -exec python3 -c "import json; json.load(open('{}'))" \; 2>&1 | grep -B1 "Error"
find . -name "*.yml" -o -name "*.yaml" | head -10
```

#### **3.2 Workflow Configuration Check**
```bash
find . -name ".dockstore.yml" -o -name "*.wdl" -o -name "nextflow.config" | head -10
# Check for broken paths in configs
grep -r "readMePath\|include\|import" . --include="*.yml" --include="*.wdl"
```

#### **3.3 Docker/Container References**
```bash
grep -r "docker\|container" . --include="*.wdl" --include="*.json" | head -5
# Check for version consistency
```

## 🔧 Standard Fix Patterns

### **Fix 1: Clean Git Repository**
```bash
# Remove execution artifacts
git rm -r "**/call-*/" "**/shard-*/" 2>/dev/null || true

# Stage legitimate deletions
git add -A

# Commit cleanup
git commit -m "fix: remove execution artifacts from git tracking"
```

### **Fix 2: Remove Technology Contamination**
```bash
# Node.js contamination
rm -rf node_modules/ package*.json yarn.lock

# Python cache
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete

# R artifacts  
rm -f .RData .Rhistory
```

### **Fix 3: Update .gitignore (Comprehensive)**
```gitignore
# Large data (never track)
/data/
/datasets/
/input/
/output/
*_downloads/
*_outputs/

# Execution artifacts
**/call-*/
**/shard-*/
stderr
stdout
rc
memory_retry_rc
script
*.log

# Technology-specific contamination
node_modules/
package*.json
*.lock
__pycache__/
*.pyc
.RData
.Rhistory

# System/Editor
.DS_Store
.vscode/
*.code-workspace
.claude/
.trunk/
.cache/
```

### **Fix 4: Standardize Configuration Files**
```bash
# Format JSON files
find . -name "*.json" -exec python3 -c "
import json, sys
try:
    with open('{}', 'r') as f: data = json.load(f)
    with open('{}', 'w') as f: json.dump(data, f, indent=2)
    print('Fixed: {}')
except: print('Error: {}')
" \;
```

## 🎯 Repository Purpose Alignment

### **Bioinformatics/Workflow Repository Should Have:**
✅ **Workflows:** `.wdl`, `.nf`, `.cwl` files  
✅ **Configurations:** Input JSON, parameter files  
✅ **Containers:** Dockerfiles, container definitions  
✅ **Documentation:** Setup guides, usage examples  
✅ **Examples:** Test data references (NOT actual large data)

### **Should NOT Have:**
❌ **Execution outputs:** Results, logs, intermediate files  
❌ **Large datasets:** Raw data files > 1MB  
❌ **Technology contamination:** Node.js in Python project, etc.  
❌ **IDE configurations:** Editor-specific settings  
❌ **System files:** OS-specific temporary files

## 🚀 Quick Start Commands

### **Full Repository Health Check:**
```bash
# Run this single command for complete audit
bash -c "
echo '=== GIT STATUS ==='
git status --porcelain | wc -l
echo '=== LARGE FILES ==='
du -sh */ | sort -hr | head -5
echo '=== CONTAMINATION CHECK ==='
find . -name 'node_modules' -o -name '*.pyc' -o -name '__pycache__' | wc -l
echo '=== CONFIG VALIDATION ==='
find . -name '*.json' | wc -l
echo 'Health check complete. See full checklist for detailed fixes.'
"
```

### **Emergency Clean Command:**
```bash
# WARNING: Review before running - removes common problematic patterns
git rm -r --cached "**/call-*/" "**/shard-*/" 2>/dev/null || true
rm -rf node_modules/ package*.json __pycache__/
find . -name "*.pyc" -delete
find . -name ".DS_Store" -delete
git add .gitignore
```

## 📊 Health Score Criteria

### **🟢 Excellent (90-100%)**
- Clean git status (0 uncommitted files)
- No contamination artifacts
- All configs validated
- Proper .gitignore coverage
- Clear purpose alignment

### **🟡 Good (70-89%)**
- Minor git issues (< 5 files)
- Minimal contamination
- Most configs valid
- Basic .gitignore present

### **🟠 Needs Work (50-69%)**
- Some git issues (5-20 files)
- Some contamination present
- Some broken configs
- Incomplete .gitignore

### **🔴 Critical (< 50%)**
- Major git issues (> 20 files)
- Significant contamination
- Multiple broken configs
- Missing/inadequate .gitignore

---

## 💡 Pro Tips

1. **Run health check before every major feature**
2. **Always fix git status before adding new content**
3. **Keep .gitignore comprehensive and project-appropriate**
4. **Separate code repositories from data repositories**
5. **Use external storage for large datasets**
6. **Validate all JSON/YAML before committing**
7. **Regular cleanup prevents major problems**

---

**Usage:** `"Please revise my repository according to REPOSITORY_HEALTH_CHECKLIST.md"`