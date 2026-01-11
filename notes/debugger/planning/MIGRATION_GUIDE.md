
# Migration Guide: Moving AHK Debugger to Its Own Repository

## Overview

This guide provides step-by-step instructions for migrating the AutoHotkey v2 Debugger Interception system from the `notes/` directory to a standalone repository.

---

## Prerequisites

- Git installed and configured
- Node.js 14+ installed
- GitHub account with repository creation permissions
- Access to the current AutoHotkey repository

---

## Phase 1: Repository Setup (Day 1)

### Step 1.1: Create GitHub Repository

```bash
# On GitHub.com
1. Click "New Repository"
2. Name: "ahk-debugger-mcp"
3. Description: "AutoHotkey v2 Debugger MCP Server - DBGp protocol interception and analysis"
4. Visibility: Public
5. Initialize with: README (temporary, will be replaced)
6. License: GNU General Public License v2.0
7. .gitignore: Node
```

### Step 1.2: Clone and Setup Local Repository

```bash
# Clone the new repository
git clone https://github.com/yourusername/ahk-debugger-mcp.git
cd ahk-debugger-mcp

# Create branch structure
git checkout -b develop
git push -u origin develop

# Set up branch protection (on GitHub)
# - Protect main branch
# - Require PR reviews
# - Require status checks
```

### Step 1.3: Create Directory Structure

```bash
# Create all directories
mkdir -p src docs examples patches tests scripts

# Create placeholder files
touch src/.gitkeep
touch examples/.gitkeep
touch patches/.gitkeep
touch tests/.gitkeep
touch scripts/.gitkeep
```

---

## Phase 2: Code Migration (Day 1-2)

### Step 2.1: Copy and Refactor Server Code

```bash
# From the AutoHotkey repository
cd /path/to/AutoHotkey/notes

# Copy the main server file
cp ahk-debugger-mcp-server.js /path/to/ahk-debugger-mcp/src/server.js
```

**Refactoring Tasks**:

1. **Extract DebugEventCache to separate file**:
```bash
# Create src/cache.js
# Move DebugEventCache class from server.js
# Add proper exports
```

2. **Extract DBGpParser to separate file**:
```bash
# Create src/parser.js
# Move DBGpParser class from server.js
# Add proper exports
```

3. **Extract DBGpProxy to separate file**:
```bash
# Create src/proxy.js
# Move DBGpProxy class from server.js
# Add proper exports
```

4. **Update server.js**:
```javascript
// src/server.js
const { DebugEventCache } = require('./cache');
const { DBGpParser } = require('./parser');
const { DBGpProxy } = require('./proxy');

// Keep only DBGpMCPServer class and main() function
```

### Step 2.2: Create Package Configuration

```bash
# Create package.json
cat > package.json << 'EOF'
{
  "name": "ahk-debugger-mcp",
  "version": "1.0.0",
  "description": "AutoHotkey v2 Debugger MCP Server - DBGp protocol interception and analysis",
  "main": "src/server.js",
  "bin": {
    "ahk-debugger-mcp": "./src/server.js"
  },
  "scripts": {
    "start": "node src/server.js",
    "test": "jest",
    "test:coverage": "jest --coverage",
    "lint": "eslint src/",
    "lint:fix": "eslint src/ --fix",
    "dev": "nodemon src/server.js"
  },
  "keywords": [
    "autohotkey",
    "debugger",
    "dbgp",
    "xdebug",
    "mcp",
    "protocol",
    "interception"
  ],
  "author": "Your Name <your.email@example.com>",
  "license": "GPL-2.0",
  "dependencies": {
    "xml2js": "^0.6.2"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "nodemon": "^3.0.2",
    "eslint": "^8.55.0"
  },
  "engines": {
    "node": ">=14.0.0"
  },
  "repository": {
    "type": "git",
    "url": "https://github.com/yourusername/ahk-debugger-mcp.git"
  },
  "bugs": {
    "url": "https://github.com/yourusername/ahk-debugger-mcp/issues"
  },
  "homepage": "https://github.com/yourusername/ahk-debugger-mcp#readme"
}
EOF

# Install dependencies
npm install
```

### Step 2.3: Add Shebang to Server

```bash
# Edit src/server.js - add at top
#!/usr/bin/env node

# Make executable
chmod +x src/server.js
```

---

## Phase 3: Documentation Migration (Day 2-3)

### Step 3.1: Copy Documentation Files

```bash
# From AutoHotkey repository notes/ directory
cd /path/to/AutoHotkey/notes

# Copy to new repository
cp QUICK_START_DEBUGGER_INTERCEPTION.md /path/to/ahk-debugger-mcp/docs/QUICK_START.md
cp DEBUGGER_ARCHITECTURE.md /path/to/ahk-debugger-mcp/docs/ARCHITECTURE.md
cp DEBUGGER_SETUP_GUIDE.md /path/to/ahk-debugger-mcp/docs/SETUP_GUIDE.md
cp DEBUGGER_INTERCEPTION_README.md /path/to/ahk-debugger-mcp/docs/API_REFERENCE.md
cp DEBUGGER_MODIFICATION_IMPLEMENTATION.md /path/to/ahk-debugger-mcp/docs/IMPLEMENTATION.md
cp DEBUGGER_PRACTICAL_EXAMPLE.md /path/to/ahk-debugger-mcp/docs/EXAMPLES.md
```

### Step 3.2: Update Documentation

For each documentation file:

1. **Update file paths**:
```bash
# Replace notes/ references
sed -i 's|notes/||g' docs/*.md

# Update source code references
sed -i 's|source/Debugger.cpp|../patches/Debugger.cpp.patch|g' docs/*.md
```

2. **Update internal links**:
```bash
# Update cross-references between docs
# Example: [Setup Guide](DEBUGGER_SETUP_GUIDE.md) → [Setup Guide](SETUP_GUIDE.md)
```

3. **Add navigation**:
```markdown
# Add to top of each doc
[← Back to Documentation](README.md)

# Add to bottom of each doc
---
[← Previous](PREVIOUS.md) | [Documentation Index](README.md) | [Next →](NEXT.md)
```

### Step 3.3: Create New Documentation Files

```bash
# Create docs/README.md (documentation index)
# Create docs/TROUBLESHOOTING.md (extract from existing docs)
# Create CONTRIBUTING.md (root level)
# Create CHANGELOG.md (root level)
```

### Step 3.4: Create Main README

```bash
# Copy the prepared README
cp /path/to/AutoHotkey/notes/NEW_REPO_README.md /path/to/ahk-debugger-mcp/README.md
```

---

## Phase 4: Examples Migration (Day 3-4)

### Step 4.1: Extract Examples from Documentation

From `DEBUGGER_PRACTICAL_EXAMPLE.md`, extract code to separate files:

```bash
# Create example files
touch examples/basic-monitor.js
touch examples/error-cache.js
touch examples/slack-notifier.js
touch examples/db-logger.js
touch examples/complete-interceptor.js
```

### Step 4.2: Create Example README

```bash
cat > examples/README.md << 'EOF'
# Examples

This directory contains practical examples of using the AHK Debugger MCP Server.

## Available Examples

- [basic-monitor.js](basic-monitor.js) - Simple event monitoring
- [error-cache.js](error-cache.js) - Error tracking and caching
- [slack-notifier.js](slack-notifier.js) - Slack integration
- [db-logger.js](db-logger.js) - SQLite database logging
- [complete-interceptor.js](complete-interceptor.js) - Full-featured implementation

## Running Examples

```bash
# Install dependencies
npm install

# Run an example
node examples/basic-monitor.js
```
EOF
```

---

## Phase 5: Patches and Integration (Day 4-5)

### Step 5.1: Create Patch Files

```bash
# Create patches for C++ modifications
cd patches

# Create Debugger.h patch
cat > Debugger.h.patch << 'EOF'
--- a/source/Debugger.h
+++ b/source/Debugger.h
@@ -260,6 +260,20 @@ class Debugger
 
 private:
+#ifdef CONFIG_DEBUGGER_LOGGING
+    struct DebugEvent {
+        const char *type;
+        const char *data;
+        size_t size;
+        DWORD timestamp;
+    };
+
+    static const int MAX_CACHED_EVENTS = 1000;
+    DebugEvent mEventCache[MAX_CACHED_EVENTS];
+    int mEventCacheIndex = 0;
+
+    void LogDebugEvent(const char *aType, const char *aData, size_t aSize);
+#endif
+
     // ... rest of class
EOF

# Create Debugger.cpp patch
cat > Debugger.cpp.patch << 'EOF'
--- a/source/Debugger.cpp
+++ b/source/Debugger.cpp
@@ -2427,6 +2427,10 @@ int Debugger::SendResponse(size_t aStartOffset)
     ASSERT(!mResponseBuf.mFailed);
     ASSERT(aStartOffset < mResponseBuf.mDataUsed);
 
+#ifdef CONFIG_DEBUGGER_LOGGING
+    LogDebugEvent("SEND", mResponseBuf.mData + aStartOffset,
+                  mResponseBuf.mDataUsed - aStartOffset);
+#endif
+
     char response_header[DEBUGGER_RESPONSE_OVERHEAD];
     // ... rest of function
EOF
```

### Step 5.2: Create Patch Application Guide

```bash
cat > patches/README.md << 'EOF'
# C++ Source Patches

These patches add event logging to the AutoHotkey v2 debugger.

## Applying Patches

```bash
cd /path/to/AutoHotkey
patch -p1 < /path/to/ahk-debugger-mcp/patches/Debugger.h.patch
patch -p1 < /path/to/ahk-debugger-mcp/patches/Debugger.cpp.patch