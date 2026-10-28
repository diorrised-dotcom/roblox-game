"""Builds tools/InstallInStudio.lua: one paste-into-Command-Bar script that creates every game script."""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def cls(name, area):
    if name.endswith(".server.luau"):
        return "Script", name[:-len(".server.luau")]
    if name.endswith(".client.luau"):
        return "LocalScript", name[:-len(".client.luau")]
    return "ModuleScript", name[:-len(".luau")]

AREAS = [("shared", "ReplicatedStorage", "Shared"),
         ("server", "ServerScriptService", "Server"),
         ("client", "StarterPlayerScripts", "Client")]

out = ["""-- LIGHTS OUT installer. Paste into View > Command Bar and press Enter (run once in an empty place).
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local SP = game:GetService("StarterPlayer")
local roots = { ReplicatedStorage = RS, ServerScriptService = SSS, StarterPlayerScripts = SP:WaitForChild("StarterPlayerScripts") }
local function folder(root, name)
	local old = roots[root]:FindFirstChild(name)
	if old then old:Destroy() end
	local f = Instance.new("Folder"); f.Name = name; f.Parent = roots[root]; return f
end
local function add(parent, class, name, source)
	local s = Instance.new(class); s.Name = name; s.Source = source; s.Parent = parent
end
"""]
for d, root, fname in AREAS:
    out.append(f'do local f = folder("{root}", "{fname}")')
    for fn in sorted(os.listdir(os.path.join(ROOT, "src", d))):
        c, n = cls(fn, d)
        src = open(os.path.join(ROOT, "src", d, fn), encoding="utf-8").read()
        lvl = 5
        while ("]" + "=" * lvl + "]") in src:
            lvl += 1
        eq = "=" * lvl
        out.append(f'add(f, "{c}", "{n}", [{eq}[\n{src}]{eq}])')
    out.append("end")
out.append('print("LIGHTS OUT installed. Press Play.")')
open(os.path.join(ROOT, "tools", "InstallInStudio.lua"), "w", encoding="utf-8").write("\n".join(out) + "\n")
print("ok")
