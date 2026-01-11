# AutoHotkey v2 Training Examples

This folder contains 5 beginner-friendly training examples demonstrating core AutoHotkey v2 concepts. Each example is self-contained, runnable, and includes detailed comments.

## Quick Start

Run any example with:
```bash
AutoHotkey64.exe training_XX_name.ahk
```

Or in WSL:
```bash
"/mnt/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe" training_XX_name.ahk
```

---

## Examples

### 1. `training_01_classes.ahk` - Classes & Object-Oriented Programming
**Lines**: ~30 | **Difficulty**: Beginner

Learn how to:
- Define classes with constructors
- Create instance properties
- Write methods
- Instantiate and use objects

**Key Concepts**:
- `class` keyword definition
- `__New()` constructor
- `this.property` assignment
- Method declarations and calls

**Output**: Two message boxes showing person names and ages

---

### 2. `training_02_arrays.ahk` - Array Operations & Filtering
**Lines**: ~35 | **Difficulty**: Beginner

Learn how to:
- Create and iterate arrays
- Filter arrays (keep values matching conditions)
- Find elements in arrays
- Transform arrays (map operations)

**Key Concepts**:
- Array literal syntax: `[value1, value2, ...]`
- `for item in array` iteration
- `Array.Push()` to add elements
- Conditional filtering with `if`
- Array indexing

**Output**: Four message boxes showing filtered, found, and transformed data

---

### 3. `training_03_maps.ahk` - Map Data Structures
**Lines**: ~30 | **Difficulty**: Beginner

Learn how to:
- Create and populate Maps (key-value storage)
- Look up values by key
- Check if keys exist
- Iterate through Map entries
- Update and count entries

**Key Concepts**:
- `Map()` constructor
- `map[key] := value` assignment
- `map.Has(key)` existence checking
- `for key, value in map` iteration
- `map.Count` property

**Output**: Five message boxes showing lookups, iterations, and counts

---

### 4. `training_04_gui.ahk` - GUI Window Creation
**Lines**: ~31 | **Difficulty**: Beginner

Learn how to:
- Create a GUI window
- Add different control types (Text, Edit, Button)
- Handle button click events
- Get and set control values
- Manage keyboard focus

**Key Concepts**:
- `Gui()` constructor
- `.Add(type, options, text)` method
- `.OnEvent(event, callback)` method
- `.Value` property for getting/setting control data
- `.Focus()` for keyboard focus
- `.Show()` to display the window

**Output**: Interactive window that responds to button clicks

---

### 5. `training_05_regex.ahk` - Regular Expressions & String Processing
**Lines**: ~30 | **Difficulty**: Beginner-Intermediate

Learn how to:
- Extract text using patterns (email extraction)
- Replace text patterns (whitespace handling)
- Validate format patterns (phone numbers)
- Find all matches in text

**Key Concepts**:
- `RegExMatch(text, pattern, &output)` for finding patterns
- `RegExReplace(text, pattern, replacement)` for replacing
- Regex anchors: `^` (start), `$` (end)
- Character classes: `\w` (word), `\d` (digit), `\s` (whitespace)
- Quantifiers: `+` (one or more), `{n}` (exactly n times)
- Grouping with parentheses for capture

**Output**: Four message boxes demonstrating pattern matching and validation

---

## Learning Path

**Recommended Order:**
1. Start with `training_01_classes.ahk` - Understand object-oriented basics
2. Move to `training_02_arrays.ahk` - Learn data collection handling
3. Try `training_03_maps.ahk` - Explore key-value storage
4. Build with `training_04_gui.ahk` - Create interactive interfaces
5. Polish with `training_05_regex.ahk` - Master text processing

## Key AHK v2 Standards Used

All examples follow these AHK v2 standards:

✓ **Expression Mode Only** - No v1 commands, all expressions
✓ **Assignment Operator** - Always use `:=` (never `=`)
✓ **Function Calls** - Always use `()` in definitions and calls
✓ **Object Syntax** - Use `this.property` and `.Method()` notation
✓ **Array Indexing** - 1-based indexing (first element is index 1)
✓ **Error Handling** - Proper `try/catch` blocks where needed

## Tips for Learning

1. **Read the comments** - Each line has explanatory comments
2. **Modify and experiment** - Change values and see what happens
3. **Add debug output** - Use `MsgBox()` to inspect variables
4. **Copy patterns** - These are templates for your own code
5. **Check error messages** - AHK's error messages are usually clear

## Common Pitfalls to Avoid

- ❌ Using `=` instead of `:=` for assignment
- ❌ Trying to use v1 commands like `Gui, Add`
- ❌ Forgetting parentheses in function calls
- ❌ Assuming 0-based array indexing
- ❌ Empty `catch` blocks without error handling

## Next Steps

After these examples, explore:
- More complex GUI layouts
- File I/O operations
- Window and process management
- Advanced class inheritance
- Hook systems and timers

---

**Created**: November 3, 2025
**Format**: AutoHotkey v2.0
**License**: Educational - Free to use and modify
