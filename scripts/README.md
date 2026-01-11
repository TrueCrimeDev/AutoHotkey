# Scripts Directory

> AutoHotkey v2 testing and utility scripts

## Overview

This directory contains AutoHotkey v2 scripts for testing, debugging, and utility purposes.

## Scripts

### Test Scripts
- **[TestScript1.ahk](TestScript1.ahk)** - Basic functionality test
- **[TestScript2.ahk](TestScript2.ahk)** - Advanced feature test
- **[test_random_script.ahk](test_random_script.ahk)** - Random behavior testing
- **[TestErrorWithLLM.ahk](TestErrorWithLLM.ahk)** - Error handling with LLM integration

### Property Descriptor Demo
- **[PropertyDescriptorDemo.ahk](PropertyDescriptorDemo.ahk)** - Imports the shared property descriptor module and logs example outputs

### Usage

1. **Run individual scripts**:
```bash
AutoHotkey.exe TestScript1.ahk
```

2. **Run with debugger**:
```bash
AutoHotkey.exe /debug TestScript1.ahk
```

3. **Test error handling**:
```bash
AutoHotkey.exe TestErrorWithLLM.ahk
```

4. **Run the property descriptor demo**:
```bash
AutoHotkey.exe PropertyDescriptorDemo.ahk
```

## Script Categories

### Basic Tests
- Variable manipulation
- Function definitions
- Control flow testing
- Simple GUI operations

### Advanced Tests
- Error handling scenarios
- Performance testing
- Integration testing
- LLM integration testing

### Error Testing
- Exception handling
- Error logging
- Recovery procedures
- Debugging workflows

## Development Guidelines

When adding new scripts:

1. **Naming**: Use descriptive names (TestScript3.ahk, etc.)
2. **Documentation**: Add header comments explaining purpose
3. **Error Handling**: Include proper error handling
4. **Testing**: Test with various AutoHotkey versions
5. **Cleanup**: Remove temporary files and variables

## Integration with Debugger

These scripts can be used with the [debugger system](../debugger/) for comprehensive testing:

```bash
# Start debugger server
cd ../debugger/server
node ahk-debugger-mcp-server.js

# Run script with debugging
AutoHotkey.exe /debug TestScript1.ahk
```

## Notes

- Scripts are designed for AutoHotkey v2
- Some scripts may require specific AutoHotkey versions
- Test scripts should be run in isolated environment
- Error scripts are designed to test exception handling

---

**Last Updated**: 2025-10-23  
**Status**: Organized and Ready