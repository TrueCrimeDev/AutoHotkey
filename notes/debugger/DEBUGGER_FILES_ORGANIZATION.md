# Debugging Interception Files Organization Plan

## Current Files in notes/ Directory

### Debugger-Related Files (9 files)
1. `ahk-debugger-mcp-server.js` - Main MCP server implementation
2. `DEBUGGER_ARCHITECTURE.md` - System architecture
3. `DEBUGGER_INTERCEPTION_GUIDE.md` - Technical guide
4. `DEBUGGER_INTERCEPTION_README.md` - Complete reference
5. `DEBUGGER_INTERCEPTION_SUMMARY.md` - High-level overview
6. `DEBUGGER_MODIFICATION_IMPLEMENTATION.md` - C++ modifications
7. `DEBUGGER_PRACTICAL_EXAMPLE.md` - Usage examples
8. `DEBUGGER_SETUP_GUIDE.md` - Setup instructions
9. `DEBUGGER_SOLUTION_INDEX.md` - Complete index
10. `QUICK_START_DEBUGGER_INTERCEPTION.md` - Quick start

### Planning Files (4 files) - Already Created
1. `AHK_DEBUGGER_REPO_PLAN.md` - Repository structure plan
2. `DOCUMENTATION_HIERARCHY.md` - Documentation organization
3. `MIGRATION_GUIDE.md` - Migration instructions
4. `NEW_REPO_README.md` - New repository README
5. `REPOSITORY_SUMMARY.md` - Executive summary

### Other Files (Not debugger-related)
- PropertyDescriptor files (separate project)
- VS_CODE_PROBLEMS.md
- README.md

## Proposed Organization Structure

```
notes/
├── debugger/                          # All debugger-related files
│   ├── README.md                      # Debugger project index
│   ├── server/                        # MCP server files
│   │   ├── ahk-debugger-mcp-server.js
│   │   └── README.md                  # Server documentation
│   ├── docs/                          # Documentation
│   │   ├── 00_SOLUTION_INDEX.md       # Main index (renamed)
│   │   ├── 01_QUICK_START.md          # Quick start (renamed)
│   │   ├── 02_ARCHITECTURE.md         # Architecture (renamed)
│   │   ├── 03_INTERCEPTION_GUIDE.md   # Technical guide (renamed)
│   │   ├── 04_SETUP_GUIDE.md          # Setup (renamed)
│   │   ├── 05_IMPLEMENTATION.md       # C++ mods (renamed)
│   │   ├── 06_PRACTICAL_EXAMPLES.md   # Examples (renamed)
│   │   ├── 07_API_REFERENCE.md        # Reference (renamed)
│   │   └── 08_INTERCEPTION_SUMMARY.md # Summary (renamed)
│   ├── planning/                      # Planning documents
│   │   ├── REPO_PLAN.md               # Repository plan (renamed)
│   │   ├── DOCS_HIERARCHY.md          # Documentation hierarchy (renamed)
│   │   ├── MIGRATION_GUIDE.md         # Migration guide (renamed)
│   │   ├── NEW_REPO_README.md         # New README (renamed)
│   │   └── REPOSITORY_SUMMARY.md      # Summary (renamed)
│   └── examples/                      # Extracted examples
│       ├── basic-monitor.js
│       ├── error-cache.js
│       ├── slack-notifier.js
│       ├── db-logger.js
│       └── complete-interceptor.js
├── property-descriptor/               # PropertyDescriptor project
│   ├── README.md
│   ├── GUIDE.md
│   ├── QUICK_REFERENCE.md
│   ├── INTEGRATION.md
│   └── EXAMPLE.ahk
└── README.md                          # Main notes index
```

## File Renaming Plan

### Documentation Files (Numbered for order)
| Current Name | New Name | Purpose |
|--------------|----------|---------|
| `DEBUGGER_SOLUTION_INDEX.md` | `00_SOLUTION_INDEX.md` | Main index |
| `QUICK_START_DEBUGGER_INTERCEPTION.md` | `01_QUICK_START.md` | Quick start |
| `DEBUGGER_ARCHITECTURE.md` | `02_ARCHITECTURE.md` | Architecture |
| `DEBUGGER_INTERCEPTION_GUIDE.md` | `03_INTERCEPTION_GUIDE.md` | Technical guide |
| `DEBUGGER_SETUP_GUIDE.md` | `04_SETUP_GUIDE.md` | Setup |
| `DEBUGGER_MODIFICATION_IMPLEMENTATION.md` | `05_IMPLEMENTATION.md` | C++ mods |
| `DEBUGGER_PRACTICAL_EXAMPLE.md` | `06_PRACTICAL_EXAMPLES.md` | Examples |
| `DEBUGGER_INTERCEPTION_README.md` | `07_API_REFERENCE.md` | Reference |
| `DEBUGGER_INTERCEPTION_SUMMARY.md` | `08_INTERCEPTION_SUMMARY.md` | Summary |

### Planning Files
| Current Name | New Name | Purpose |
|--------------|----------|---------|
| `AHK_DEBUGGER_REPO_PLAN.md` | `REPO_PLAN.md` | Repository plan |
| `DOCUMENTATION_HIERARCHY.md` | `DOCS_HIERARCHY.md` | Documentation hierarchy |
| `MIGRATION_GUIDE.md` | `MIGRATION_GUIDE.md` | Migration guide |
| `NEW_REPO_README.md` | `NEW_REPO_README.md` | New README |
| `REPOSITORY_SUMMARY.md` | `REPOSITORY_SUMMARY.md` | Summary |

## Cross-Reference Updates Needed

### Internal Links to Update
1. All references between debugger docs
2. Links from planning docs to debugger docs
3. Links from debugger docs to planning docs
4. Links to the server file
5. Links to examples

### Link Format Changes
- `DEBUGGER_*.md` → `docs/##_*.md`
- `ahk-debugger-mcp-server.js` → `server/ahk-debugger-mcp-server.js`
- Planning files → `planning/*.md`

## Benefits of This Organization

### Immediate Benefits
- ✅ Clear separation of debugger vs other projects
- ✅ Logical grouping by function (docs, server, planning)
- ✅ Numbered documentation for reading order
- ✅ Easy navigation with README files
- ✅ Preparation for eventual migration

### Migration Benefits
- ✅ Files already in correct structure
- ✅ Easy to copy entire `debugger/` directory
- ✅ Minimal path updates needed
- ✅ Clear separation of concerns

## Implementation Steps

### Step 1: Create Directory Structure
```bash
mkdir -p notes/debugger/{server,docs,planning,examples}
mkdir -p notes/property-descriptor
```

### Step 2: Move Server File
```bash
mv notes/ahk-debugger-mcp-server.js notes/debugger/server/
```

### Step 3: Move Documentation Files
```bash
# Move and rename documentation files
mv notes/DEBUGGER_SOLUTION_INDEX.md notes/debugger/docs/00_SOLUTION_INDEX.md
mv notes/QUICK_START_DEBUGGER_INTERCEPTION.md notes/debugger/docs/01_QUICK_START.md
# ... continue for all documentation files
```

### Step 4: Move Planning Files
```bash
mv notes/AHK_DEBUGGER_REPO_PLAN.md notes/debugger/planning/REPO_PLAN.md
mv notes/DOCUMENTATION_HIERARCHY.md notes/debugger/planning/DOCS_HIERARCHY.md
# ... continue for all planning files
```

### Step 5: Extract Examples
```bash
# Extract code examples from DEBUGGER_PRACTICAL_EXAMPLE.md
# Create separate .js files in examples/ directory
```

### Step 6: Create README Files
- `notes/debugger/README.md` - Debugger project index
- `notes/debugger/server/README.md` - Server documentation
- `notes/property-descriptor/README.md` - PropertyDescriptor index
- Update `notes/README.md` - Main index

### Step 7: Update Cross-References
- Update all internal links
- Update file paths in documentation
- Test all links work correctly

## Next Actions

1. **Create directory structure**
2. **Move files to new locations**
3. **Rename files with numbering**
4. **Extract examples to separate files**
5. **Create README files**
6. **Update all cross-references**
7. **Test navigation**

This organization will make the debugging project much more manageable and prepare it for eventual migration to its own repository.