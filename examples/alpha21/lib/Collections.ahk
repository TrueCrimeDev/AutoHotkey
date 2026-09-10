; Collections — multiple modules in one file.
; In alpha.21:
;   - Each #Module requires a valid identifier
;   - Modules end at the next #Module or end of file
;   - Module names are private to this file

#Module Stack

class Stack
{
    __New()
    {
        this.items := []
    }

    Push(value)
    {
        this.items.Push(value)
    }

    Pop()
    {
        if this.items.Length = 0
            throw Error("Stack is empty")
        return this.items.Pop()
    }

    Peek()
    {
        if this.items.Length = 0
            throw Error("Stack is empty")
        return this.items[this.items.Length]
    }

    Size()
    {
        return this.items.Length
    }

    IsEmpty()
    {
        return this.items.Length = 0
    }
}

#Module Queue

class Queue
{
    __New()
    {
        this.items := []
    }

    Enqueue(value)
    {
        this.items.Push(value)
    }

    Dequeue()
    {
        if this.items.Length = 0
            throw Error("Queue is empty")
        return this.items.RemoveAt(1)
    }

    Front()
    {
        if this.items.Length = 0
            throw Error("Queue is empty")
        return this.items[1]
    }

    Size()
    {
        return this.items.Length
    }
}
