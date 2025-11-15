#Requires AutoHotkey v2.0

; Test Script for ConfigManager Property Descriptor

; Import the necessary module or source file
#Include "..\\..\\notes\\property-descriptor\\EXAMPLE_PropertyDescriptorBracketNotation.ahk"

; Test suite for ConfigManager class
class ConfigManagerTest {
    static Test() {
        cfg := ConfigManager()
        
        ; Set configuration values
        cfg.Set("database.host", "localhost")
        cfg.Set("database.port", 5432)
        cfg.Set("api.timeout", 30)
        
        ; Test getting all config
        allConfig := cfg.Get
        if (allConfig.Count != 3)
            throw Error("Test failed: Expected 3 config items, got " allConfig.Count)
        
        ; Test getting specific values
        hostValue := cfg.Get["database.host"]
        if (hostValue != "localhost")
            throw Error("Test failed: Expected 'localhost', got " hostValue)
        
        portValue := cfg.Get["database.port"]
        if (portValue != 5432)
            throw Error("Test failed: Expected 5432, got " portValue)
        
        timeoutValue := cfg.Get["api.timeout"]
        if (timeoutValue != 30)
            throw Error("Test failed: Expected 30, got " timeoutValue)
        
        ; Test attempting to get non-existent key
        try {
            nonExistentValue := cfg.Get["nonexistent.key"]
            throw Error("Test failed: Should have thrown KeyError for non-existent key")
        } catch as err {
            ; Expected behavior
            if (err.What != "KeyError")
                throw Error("Test failed: Unexpected error type")
        }
        
        MsgBox "ConfigManager Property Descriptor Test Passed!"
    }
}

; Run the test
ConfigManagerTest.Test()