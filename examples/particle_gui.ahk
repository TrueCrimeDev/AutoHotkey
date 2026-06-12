/*
particle_gui.ahk — Dark mode particle editor using structs + OOP

Demonstrates:
  - Structs as data models backing GUI controls
  - Full dark mode via DarkGui (Alpha22_Example.ahk)
  - OOP architecture: ParticleSystem, ParticleEditor classes
  - Struct arrays for contiguous particle storage

Requires: Alpha22_Example.ahk in same directory (DarkGui framework)
*/
#Requires AutoHotkey v2.1-alpha.26
#Include Alpha22_Example.ahk

; ── Data Model ──────────────────────────────────────

Struct Particle {
    x: Float32
    y: Float32
    z: Float32
    vx: Float32
    vy: Float32
    vz: Float32
    mass: Float32
    lifetime: Float32
}

class ParticleSystem {
    particles := []

    Add(x := 0, y := 0, z := 0, vx := 0, vy := 0, vz := 0, mass := 1.0, life := 5.0) {
        p := Particle()
        p.x := x, p.y := y, p.z := z
        p.vx := vx, p.vy := vy, p.vz := vz
        p.mass := mass, p.lifetime := life
        this.particles.Push(p)
        return p
    }

    AddRandom() {
        return this.Add(
            Random(20, 350), Random(20, 250), 0,
            Random(-30, 30) / 10, Random(-30, 30) / 10, 0,
            Random(1, 50) / 10, Random(10, 100) / 10
        )
    }

    Remove(index) {
        if index >= 1 && index <= this.particles.Length
            this.particles.RemoveAt(index)
    }

    Count => this.particles.Length

    __Item[index] {
        get => this.particles[index]
    }

    MemoryUsage => this.Count * Particle().Size
}

; ── GUI ─────────────────────────────────────────────

class ParticleEditor {
    static Fields := ["x", "y", "z", "vx", "vy", "vz", "mass", "lifetime"]

    __New(system) {
        this.system := system
        this.edits := Map()
        this.selected := 0
        this.Build()
        this.RefreshList()
    }

    Build() {
        this.gui := DarkGui("+Resize", "Particle Editor — Struct Demo")
        this.gui.SetFont("s10", "Segoe UI")
        this.gui.OnEvent("Close", (*) => ExitApp())

        ; Left panel: particle list
        this.gui.Add("Text", "x16 y12 w160 Section", "PARTICLES")
        this.lv := this.gui.Add("ListView",
            "xs y+6 w170 h300 +Grid +LV0x14000", ["#", "X", "Y", "Mass"])
        this.lv.OnEvent("ItemSelect", (ctrl, item, sel) => this.OnSelect(item, sel))

        ; Right panel: property editor
        this.gui.Add("Text", "x210 y12 w180 Section", "PROPERTIES")

        yPos := 38
        for name in ParticleEditor.Fields {
            this.gui.SetFont("s9 c0x808080")
            this.gui.Add("Text", "x210 y" yPos " w65 h22 +0x200", name)
            this.gui.SetFont("s10")
            this.edits[name] := this.gui.Add("Edit", "x280 y" (yPos - 1) " w130 h24", "")
            yPos += 32
        }

        ; Buttons
        yPos += 8
        btnApply := this.gui.Add("Button", "x210 y" yPos " w95 h32 +Accent", "Apply")
        btnApply.OnEvent("Click", (*) => this.OnApply())

        btnAdd := this.gui.Add("Button", "x312 y" yPos " w98 h32", "Add New")
        btnAdd.OnEvent("Click", (*) => this.OnAdd())

        btnRemove := this.gui.Add("Button", "x210 y" (yPos + 40) " w95 h32", "Remove")
        btnRemove.OnEvent("Click", (*) => this.OnRemove())

        btnClear := this.gui.Add("Button", "x312 y" (yPos + 40) " w98 h32", "Clear All")
        btnClear.OnEvent("Click", (*) => this.OnClear())

        ; Status bar
        this.gui.SetFont("s9 c0x606060")
        this.status := this.gui.Add("Text", "x16 y" (yPos + 82) " w400 h20", "")

        this.gui.Show("w425 h" (yPos + 108))
        this.UpdateStatus()
    }

    OnSelect(item, sel) {
        if !sel || item < 1 || item > this.system.Count
            return
        this.selected := item
        p := this.system[item]
        this.edits["x"].Value := Format("{:.2f}", p.x)
        this.edits["y"].Value := Format("{:.2f}", p.y)
        this.edits["z"].Value := Format("{:.2f}", p.z)
        this.edits["vx"].Value := Format("{:.2f}", p.vx)
        this.edits["vy"].Value := Format("{:.2f}", p.vy)
        this.edits["vz"].Value := Format("{:.2f}", p.vz)
        this.edits["mass"].Value := Format("{:.2f}", p.mass)
        this.edits["lifetime"].Value := Format("{:.2f}", p.lifetime)
        this.UpdateStatus(Format("Selected particle {}", item))
    }

    OnApply() {
        if !this.selected || this.selected > this.system.Count {
            this.UpdateStatus("Select a particle first")
            return
        }
        p := this.system[this.selected]
        p.x := Number(this.edits["x"].Value)
        p.y := Number(this.edits["y"].Value)
        p.z := Number(this.edits["z"].Value)
        p.vx := Number(this.edits["vx"].Value)
        p.vy := Number(this.edits["vy"].Value)
        p.vz := Number(this.edits["vz"].Value)
        p.mass := Number(this.edits["mass"].Value)
        p.lifetime := Number(this.edits["lifetime"].Value)
        this.RefreshList()
        this.lv.Modify(this.selected, "Select Focus")
        this.UpdateStatus(Format("Updated particle {}", this.selected))
    }

    OnAdd() {
        this.system.AddRandom()
        this.RefreshList()
        this.selected := this.system.Count
        this.lv.Modify(this.selected, "Select Focus")
        this.UpdateStatus(Format("Added particle {}", this.system.Count))
    }

    OnRemove() {
        if !this.selected || this.selected > this.system.Count {
            this.UpdateStatus("Select a particle first")
            return
        }
        removed := this.selected
        this.system.Remove(this.selected)
        this.selected := 0
        this.ClearEdits()
        this.RefreshList()
        this.UpdateStatus(Format("Removed particle {}", removed))
    }

    OnClear() {
        this.system.particles := []
        this.selected := 0
        this.ClearEdits()
        this.RefreshList()
        this.UpdateStatus("Cleared all particles")
    }

    ClearEdits() {
        for name in ParticleEditor.Fields
            this.edits[name].Value := ""
    }

    RefreshList() {
        this.lv.Delete()
        loop this.system.Count {
            p := this.system[A_Index]
            this.lv.Add(, A_Index,
                Format("{:.0f}", p.x),
                Format("{:.0f}", p.y),
                Format("{:.1f}", p.mass))
        }
        this.lv.ModifyCol(1, 30)
        this.lv.ModifyCol(2, 42)
        this.lv.ModifyCol(3, 42)
        this.lv.ModifyCol(4, 45)
    }

    UpdateStatus(msg := "") {
        mem := Format("{:.1f}", this.system.MemoryUsage / 1024)
        base := Format("{} particles | {} KB struct memory", this.system.Count, mem)
        this.status.Value := msg ? msg " — " base : base
    }
}

; ── Main ────────────────────────────────────────────

sys := ParticleSystem()
sys.Add(120, 80, 0, 1.5, -0.8, 0, 1.0, 5.0)
sys.Add(200, 150, 0, -1.0, 2.0, 0, 0.5, 3.0)
sys.Add(80, 200, 0, 0.5, 0.5, 0, 2.0, 8.0)

editor := ParticleEditor(sys)
