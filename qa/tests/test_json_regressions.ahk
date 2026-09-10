#Requires AutoHotkey v2.1-alpha.30
; JSON edits must preserve current values and the types of untouched items.
#Include ..\Assert.ahk

edited := JSON.Parse('[true,false,null]')
edited[1] := 0
edited[2] := 1
edited[3] := "x"
Assert.eq(JSON.Stringify(edited), '[0,1,"x"]', "json.edit.assignment")

sameValue := JSON.Parse('[true,false,null]')
sameValue[1] := 1
sameValue[2] := 0
sameValue[3] := ""
Assert.eq(JSON.Stringify(sameValue), '[1,0,""]', "json.edit.assignment.clears.types")

removed := JSON.Parse('[true,false,null]')
removed.RemoveAt(1)
Assert.eq(JSON.Stringify(removed), '[false,null]', "json.edit.remove.shifts.types")
removed.Push(7)
Assert.eq(JSON.Stringify(removed), '[false,null,7]', "json.edit.remove.push.original.length")

inserted := JSON.Parse('[true,false,null]')
inserted.InsertAt(2, "new", JSON.True)
Assert.eq(JSON.Stringify(inserted), '[true,"new",true,false,null]', "json.edit.insert.shifts.types")
inserted.Pop()
Assert.eq(JSON.Stringify(inserted), '[true,"new",true,false]', "json.edit.pop.preserves.types")

deleted := JSON.Parse('[true,false,null]')
deleted.Delete(1)
Assert.eq(JSON.Stringify(deleted), '[null,false,null]', "json.edit.delete.leaves.hole")
deleted[1] := "replacement"
Assert.eq(JSON.Stringify(deleted), '["replacement",false,null]', "json.edit.deleted.assignment")

resized := JSON.Parse('[true,false,null]')
resized.Length := 1
resized.Length := 3
Assert.eq(JSON.Stringify(resized), '[true,null,null]', "json.edit.length.no.stale.types")
resized[-1] := JSON.False
Assert.eq(JSON.Stringify(resized), '[true,null,false]', "json.edit.negative.index.singleton")

capacity := JSON.Parse('[true,false,null]')
capacity.Capacity := 1
capacity.Push("x", "y")
Assert.eq(JSON.Stringify(capacity), '[true,"x","y"]', "json.edit.capacity.shrink")

original := JSON.Parse('[true,false,null]')
original.Capacity := 10
copied := original.Clone()
Assert.eq(JSON.Stringify(copied), '[true,false,null]', "json.edit.clone.types")
Assert.eq(copied.Capacity, 10, "json.edit.clone.capacity")
copied[1] := "clone"
copied.RemoveAt(2)
Assert.eq(JSON.Stringify(copied), '["clone",null]', "json.edit.clone.mutations")
Assert.eq(JSON.Stringify(original), '[true,false,null]', "json.edit.clone.independent")

; A key that cannot be represented must not overwrite a different key.
nulKey := '{"a\u0000x":1,"a\u0000y":2}'
Assert.throws(() => JSON.Parse(nulKey), "json.key.nul.reject", "UnsupportedKey")
Assert.throws(() => JSON.Parse(nulKey, {Container:"Map"}), "json.key.nul.map.reject", "UnsupportedKey")
keyVerdict := JSON.Validate(nulKey)
Assert.falsy(keyVerdict.Valid, "json.key.nul.validate")
Assert.eq(keyVerdict.Code, "UnsupportedKey", "json.key.nul.validate.code")
Assert.eq(JSON.Stringify(JSON.Parse('"a\u0000b"')), '"a\u0000b"', "json.string.nul.still.supported")

; A scanner failure while consuming trailing comments is still a parse error.
for badComment in ['[] /*', '[] /*unfinished', '[] /* ok */ /*', '[] /*`n'] {
    Assert.throws(() => JSON.Parse(badComment, {AllowComments:true}), "json.comment.parse." A_Index, "UnexpectedEnd")
    verdict := JSON.Validate(badComment, {AllowComments:true})
    Assert.falsy(verdict.Valid, "json.comment.validate." A_Index)
    Assert.eq(verdict.Code, "UnexpectedEnd", "json.comment.validate.code." A_Index)
    Assert.throws(() => ParseCommentAt(badComment), "json.comment.parseat." A_Index, "UnexpectedEnd")
}
Assert.eq(JSON.Stringify(JSON.Parse('[] /* finished */', {AllowComments:true})), '[]', "json.comment.closed")
Assert.truthy(JSON.Validate('[] // ends at EOF', {AllowComments:true}).Valid, "json.comment.line.eof")

; Catching malformed nested documents must release the unfinished child too.
; Compare private commit after warming the allocator; the old parser grows by
; tens of MB here, while a correct parser reuses its bounded working allocation.
payload := ""
loop 1024
    payload .= '"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",'
for malformed in ['{"child":[' payload '?]}', '[[' payload '?]]'] {
    loop 8
        IgnoreInvalidJson(malformed)
    beforeBytes := PrivateBytes()
    loop 128
        IgnoreInvalidJson(malformed)
    growth := PrivateBytes() - beforeBytes
    Assert.truthy(growth < 4 * 1024 * 1024, "json.failure.releases.child." A_Index " growth=" growth)
}

Assert.Summary()

ParseCommentAt(text) {
    pos := 1
    return JSON.ParseAt(text, &pos, {AllowComments:true})
}

IgnoreInvalidJson(text) {
    try JSON.Parse(text)
    catch JSONError
        return
    throw Error("Malformed test fixture unexpectedly parsed")
}

PrivateBytes() {
    size := A_PtrSize = 8 ? 80 : 44
    counters := Buffer(size, 0)
    NumPut("UInt", size, counters)
    if !DllCall("Psapi\GetProcessMemoryInfo", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "Ptr", counters, "UInt", size)
        throw OSError()
    return NumGet(counters, size - A_PtrSize, "UPtr")
}
