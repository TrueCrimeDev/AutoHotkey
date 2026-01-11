# DebuggerInterceptor Test Harness Documentation

## Overview

The DebuggerInterceptor Test Harness is a comprehensive testing suite designed to validate the functionality, performance, and reliability of the DebuggerInterceptor system. This document provides detailed information about the test harness architecture, test categories, usage instructions, and best practices.

## Test Harness Architecture

### Core Components

1. **TestHarness Class**: Main class that orchestrates all testing activities
2. **Test Configuration**: Global variables for tracking test results
3. **Test Environment**: Setup and teardown procedures
4. **Test Suites**: Organized categories of tests
5. **Reporting System**: Comprehensive test result generation

### Test Categories

The test harness includes 6 major test categories:

#### 1. Error Logger Tests
- **Basic Logging Functionality**: Validates all log levels (DEBUG, INFO, WARN, ERROR, FATAL)
- **Error Interception**: Tests automatic error capture and handling
- **Log File Creation**: Verifies log file generation and management
- **Log Rotation**: Tests automatic log archival when size limits are reached
- **Stack Trace Capture**: Validates comprehensive error context recording

#### 2. Log Viewer Tests
- **LogViewer Initialization**: Tests GUI component creation
- **Log Filtering**: Validates level-based filtering functionality
- **Log Search**: Tests text search capabilities

#### 3. Integration Tests
- **System Integration**: Validates ErrorLogger + LogViewer interaction
- **Configuration Persistence**: Tests setting retention and application

#### 4. Performance Tests
- **Logging Performance**: Measures logs per second throughput
- **LogViewer Refresh Performance**: Tests GUI update efficiency

#### 5. Edge Case Tests
- **Large Error Objects**: Tests handling of complex error data
- **Rapid Error Generation**: Validates system resilience under load
- **Special Characters**: Tests Unicode, emoji, and formatting handling

#### 6. Configuration Tests
- **Configuration Validation**: Tests all configurable options
- **Environment Setup**: Validates test environment isolation

## Test Harness Features

### Automated Testing
- **Self-contained execution**: Runs all tests with single command
- **Automatic environment setup**: Creates test directories and configurations
- **Self-cleaning**: Restores original environment after testing
- **Comprehensive reporting**: Generates detailed test reports

### Performance Benchmarking
- **Throughput measurement**: Logs per second metrics
- **Response time tracking**: GUI refresh performance
- **Threshold validation**: Performance requirements enforcement

### Error Simulation
- **Controlled error generation**: Safe error creation for testing
- **Exception handling validation**: Error recovery testing
- **Edge case coverage**: Boundary condition testing

### Configuration Management
- **Test environment isolation**: Separate test configuration
- **Original state preservation**: Configuration backup/restore
- **Customizable thresholds**: Adjustable performance criteria

## Usage Instructions

### Basic Usage

1. **Run all tests**:
   ```autohotkey
   #Include Tests\DebuggerInterceptor_TestHarness.ahk
   ```

2. **Run from command line**:
   ```bash
   AutoHotkey.exe RunDebuggerInterceptorTests.ahk
   ```

### Advanced Usage

1. **Run specific test suites**:
   ```autohotkey
   #Include Tests\DebuggerInterceptor_TestHarness.ahk
   harness := TestHarness()
   harness._RunErrorLoggerTests()  ; Run only ErrorLogger tests
   ```

2. **Custom configuration**:
   ```autohotkey
   #Include Tests\DebuggerInterceptor_TestHarness.ahk
   ; Set custom parameters before running
   ErrorLogger.Config["logLevel"] := "ERROR"
   ErrorLogger.Config["maxLogSize"] := 2048
   TestHarness.RunAllTests()
   ```

3. **Test report analysis**:
   ```autohotkey
   #Include Tests\DebuggerInterceptor_TestHarness.ahk
   ; After tests complete, analyze results
   report := TestResults
   for testName, result in report {
       if (!InStr(result, "PASS")) {
           ; Custom failure handling logic
       }
   }
   ```

## Test Environment

### Configuration Parameters

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| `logLevel` | "DEBUG" | Minimum log level to record |
| `logDirectory` | "TestOutput" | Directory for test log files |
| `logFilePrefix` | "TestLog_" | Prefix for test log filenames |
| `maxLogSize` | 1024 bytes | Maximum log size before rotation |
| `suppressErrorDialog` | true | Hide system error dialogs during testing |
| `copyToClipboard` | false | Disable auto-copy to clipboard |

### Performance Thresholds

| Test | Threshold | Description |
|------|-----------|-------------|
| Logging Performance | ≥50 logs/sec | Minimum acceptable logging throughput |
| LogViewer Performance | ≥2 refreshes/sec | Minimum GUI refresh rate |
| Error Logging Success | ≥80% | Minimum error capture rate |
| Special Character Success | ≥80% | Minimum special character handling |

## Test Report Format

### Report Structure

```
DEBUGGERINTERCEPTOR TEST HARNESS REPORT
Generated: [timestamp]
AutoHotkey Version: [version]

TEST SUMMARY:
Total Tests: [count]
Passed: [count]
Failed: [count]
Success Rate: [percentage]%

DETAILED RESULTS:
[Test Name]: [PASS/FAIL]
  Result: [detailed result]

PERFORMANCE METRICS:
[Performance Test]: [metric value]

RECOMMENDATIONS:
[System status and suggestions]

TEST ENVIRONMENT:
Log Directory: [path]
Log Level: [level]
Max Log Size: [size] bytes
Suppress Error Dialogs: [true/false]
```

### Report Location

Test reports are saved to:
```
TestOutput\TestReport_[timestamp].txt
```

## Test Development Guide

### Creating New Tests

1. **Follow existing patterns**: Use the same structure as existing tests
2. **Add to appropriate category**: Place tests in relevant test suites
3. **Use consistent naming**: Follow `Test[Feature][Scenario]` naming convention
4. **Include proper cleanup**: Ensure tests restore environment state
5. **Add performance metrics**: Include timing and throughput measurements where applicable

### Test Best Practices

1. **Isolate test environment**: Use test-specific directories and configurations
2. **Validate assumptions**: Check prerequisites before test execution
3. **Handle exceptions gracefully**: Provide meaningful error messages
4. **Clean up resources**: Remove temporary files and restore configurations
5. **Document test purpose**: Include clear comments explaining test objectives

## Integration with Existing Tests

The test harness integrates with existing test infrastructure:

- **JSON Tests**: Validates core AutoHotkey functionality
- **Property Descriptor Tests**: Tests advanced object property handling
- **Example Scripts**: Demonstrates real-world usage patterns

## Performance Optimization

### Test Execution Optimization

1. **Parallel test execution**: Consider running independent tests concurrently
2. **Selective test running**: Run only relevant tests during development
3. **Test result caching**: Cache results for unchanged components
4. **Performance profiling**: Identify and optimize slow tests

### System Performance Tips

1. **Reduce log verbosity**: Set appropriate log levels for testing
2. **Limit file I/O**: Use memory-based logging for performance tests
3. **Optimize GUI tests**: Minimize GUI operations in automated tests
4. **Batch operations**: Group similar operations to reduce overhead

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Test files not found | Verify working directory and include paths |
| Permission errors | Check file system permissions |
| Missing dependencies | Ensure all required files are present |
| Performance below thresholds | Check system resources and configuration |
| GUI tests failing | Verify display settings and window management |

### Debugging Tests

1. **Enable debug logging**: Set `logLevel` to "DEBUG" for detailed output
2. **Isolate problematic tests**: Run individual test suites
3. **Review test reports**: Analyze detailed failure information
4. **Check system resources**: Monitor CPU, memory, and disk usage
5. **Validate environment**: Verify AutoHotkey version and configuration

## Test Harness Maintenance

### Updating Tests

1. **Regular review**: Update tests to match new features
2. **Performance tuning**: Adjust thresholds as system improves
3. **Test coverage expansion**: Add tests for new functionality
4. **Deprecation handling**: Remove or update obsolete tests

### Version Compatibility

| AutoHotkey Version | Test Harness Compatibility |
|--------------------|-----------------------------|
| v2.1-alpha.17+ | Full compatibility |
| v2.1-alpha.16 | Partial compatibility (missing some features) |
| v2.0 | Limited compatibility (core tests only) |

## Test Harness Summary

The DebuggerInterceptor Test Harness provides:

✅ **Comprehensive coverage**: Tests all major system components
✅ **Automated execution**: Single-command test running
✅ **Performance validation**: Benchmarking and threshold testing
✅ **Detailed reporting**: Comprehensive test result analysis
✅ **Environment isolation**: Safe testing without system impact
✅ **Extensible architecture**: Easy to add new tests
✅ **Integration ready**: Works with existing test infrastructure

This test harness ensures the DebuggerInterceptor system maintains high quality, reliability, and performance across all supported scenarios and edge cases.
