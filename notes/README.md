# Notes Directory

> This directory contains organized documentation and examples for AutoHotkey v2 projects

## Directory Structure

```
notes/
├── README.md                      # This file - directory overview
├── DEBUGGER_FILES_ORGANIZATION.md # Debugger organization plan
├── VS_CODE_PROBLEMS.md             # VS Code issues and solutions
├── debugger/                       # AutoHotkey v2 Debugger Interception System
│   ├── README.md                   # Debugger project overview
│   ├── server/                     # MCP server implementation
│   │   ├── ahk-debugger-mcp-server.js
│   │   └── README.md               # Server documentation
│   ├── docs/                       # Complete debugger documentation
│   │   ├── 00_SOLUTION_INDEX.md    # Main documentation index
│   │   ├── 01_QUICK_START.md       # 5-minute setup guide
│   │   ├── 02_ARCHITECTURE.md      # System architecture
│   │   ├── 03_INTERCEPTION_GUIDE.md # Technical implementation guide
│   │   ├── 04_SETUP_GUIDE.md       # Detailed setup instructions
│   │   ├── 05_IMPLEMENTATION.md    # C++ source modifications
│   │   ├── 06_PRACTICAL_EXAMPLES.md # Usage examples
│   │   ├── 07_API_REFERENCE.md     # Complete API reference
│   │   └── 08_INTERCEPTION_SUMMARY.md # High-level summary
│   ├── planning/                   # Repository planning documents
│   │   ├── REPO_PLAN.md            # Repository structure plan
│   │   ├── DOCS_HIERARCHY.md       # Documentation organization
│   │   ├── MIGRATION_GUIDE.md      # Migration instructions
│   │   ├── NEW_REPO_README.md      # New repository README
│   │   └── REPOSITORY_SUMMARY.md   # Executive summary
│   └── examples/                   # Practical usage examples
└── property-descriptor/            # PropertyDescriptor bracket notation
    ├── README.md                   # Project overview
    ├── GUIDE_PropertyDescriptorBracketNotation.md
    ├── GUIDE_PropertyDescriptorQuickReference.md
    ├── INTEGRATION_PropertyDescriptorBracketNotation.md
    └── EXAMPLE_PropertyDescriptorBracketNotation.ahk
```

## Projects

### 1. AutoHotkey v2 Debugger Interception System

**Location**: [`debugger/`](debugger/)

A comprehensive DBGp protocol interception and analysis system for AutoHotkey v2 debugging sessions.

**Key Features**:
- Complete DBGp protocol interception
- Real-time event caching with intelligent indexing
- MCP (Model Context Protocol) interface
- Transparent proxy forwarding to IDE debuggers
- Extensive documentation and examples

**Quick Start**:
```bash
cd debugger/server
node ahk-debugger-mcp-server.js
```

**Documentation**: Start with [debugger/docs/00_SOLUTION_INDEX.md](debugger/docs/00_SOLUTION_INDEX.md)

### 2. PropertyDescriptor Bracket Notation

**Location**: [`property-descriptor/`](property-descriptor/)

AutoHotkey v2 PropertyDescriptor implementation with bracket notation support for dynamic property access and manipulation.

**Key Features**:
- Dynamic property names
- Computed property access
- Advanced object manipulation
- Enhanced metaprogramming capabilities

**Documentation**: Start with [property-descriptor/GUIDE_PropertyDescriptorBracketNotation.md](property-descriptor/GUIDE_PropertyDescriptorBracketNotation.md)

## Other Files

- **[DEBUGGER_FILES_ORGANIZATION.md](DEBUGGER_FILES_ORGANIZATION.md)** - Organization plan for the debugger system
- **[VS_CODE_PROBLEMS.md](VS_CODE_PROBLEMS.md)** - VS Code issues and solutions

## Navigation

- For **debugging tools** and **protocol analysis**: See [`debugger/`](debugger/)
- For **object manipulation** and **metaprogramming**: See [`property-descriptor/`](property-descriptor/)
- For **organization plans**: See individual project README files

---

**Last Updated**: 2025-10-23  
**Status**: Organized and Ready