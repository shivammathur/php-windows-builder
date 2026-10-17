param([int] $ProcessId, [string] $Destination)
$ErrorActionPreference = 'Stop'
if (-not ('PgoAddressSpace' -as [type])) {
    Add-Type @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class PgoAddressSpace {
    [StructLayout(LayoutKind.Sequential)]
    public struct Region {
        public IntPtr BaseAddress, AllocationBase;
        public uint AllocationProtect;
        public UIntPtr RegionSize;
        public uint State, Protect, Type;
    }
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern UIntPtr VirtualQueryEx(IntPtr process, UIntPtr address, out Region region, UIntPtr length);
    public static Region[] Read(int pid) {
        var regions = new List<Region>();
        using (var process = Process.GetProcessById(pid)) {
            ulong address = 0;
            while (address < 0x100000000UL) {
                Region region;
                if (VirtualQueryEx(process.Handle, new UIntPtr(address), out region,
                    new UIntPtr((uint)Marshal.SizeOf<Region>())).ToUInt64() == 0) break;
                ulong next = (ulong)region.BaseAddress.ToInt64() + region.RegionSize.ToUInt64();
                if (next <= address) break;
                if (region.State != 0x10000) regions.Add(region);
                address = next;
            }
        }
        return regions.ToArray();
    }
}
'@
}
$regions = @([PgoAddressSpace]::Read($ProcessId) | ForEach-Object {
    [pscustomobject]@{
        address=$_.BaseAddress.ToInt64(); allocation=$_.AllocationBase.ToInt64()
        bytes=$_.RegionSize.ToUInt64(); state=$_.State; type=$_.Type; protection=$_.Protect
    }
})
$modules = @((Get-Process -Id $ProcessId).Modules | ForEach-Object {
    [pscustomobject]@{file=$_.FileName;base=$_.BaseAddress.ToInt64();bytes=$_.ModuleMemorySize}
})
New-Item -ItemType Directory -Force $Destination | Out-Null
[ordered]@{pid=$ProcessId;time=[DateTime]::UtcNow.ToString('o');regions=$regions;modules=$modules} |
    ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Destination "$ProcessId.json")
