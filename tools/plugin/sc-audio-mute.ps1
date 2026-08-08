<#
.SYNOPSIS
Process-scoped audio mute via Windows Core Audio (WASAPI) session volume -- no registry,
no file, no state intended to outlive the target process.

.DESCRIPTION
task018: unattended test launches must be silent by default; the first attempt at this
used the game's own HKCU registry volume settings (mute before launch, restore after) and
that went badly -- see tools/plugin/README.md "Sound" and the 2026-08-08 incident it
references. This is the replacement: mute the game's own per-application audio session
directly, the same mechanism the Windows Volume Mixer uses per-app.

Enumerates EVERY ACTIVE render endpoint (EnumAudioEndpoints, DEVICE_STATE_ACTIVE), not
just the default one. First version of this checked the default endpoint only and never
found StarCraft's session across several real attempts; a verifier found Windows' own
per-app audio policy store showing StarCraft with sessions on THREE distinct render
endpoints on the machine this was built on (onboard line-out, an HDMI output, a USB
device) -- the session was very likely live the whole time, on an endpoint this code
never looked at. Checking every active endpoint is the actual fix; a longer timeout on
the wrong endpoint would still have found nothing.

Session identification matches by process id (IAudioSessionControl2::GetProcessId), the
same approach check-game-windows.ps1 and close-game.ps1 use for windows -- resolving "the
game" by name would hit whichever StarCraft happens to be running.

Scope, stated exactly rather than aspirationally: Set-ScProcessMuted polls for up to
-TimeoutSec at launch and then STOPS. An earlier version additionally started a
Register-ObjectEvent background timer meant to keep re-affirming the mute for the whole
game session; measured live, that timer does not fire while the calling script is inside
a Start-Sleep call (0 ticks observed across a 3s sleep -- PowerShell does not appear to
service the event queue during a plain sleep), which is most of what this script and
every test suite spend their time doing, and the timer dies with the calling pwsh process
regardless. That mechanism did not do what its own comments claimed and has been removed
rather than left in place as a false guarantee. If a session does not exist yet within
-TimeoutSec of launch (all endpoints checked, still nothing), the launch continues
audible -- there is currently no ongoing re-check after that point.

No registry key or file is written by SetMute as far as this was checked (searched both
HKCU:\...\MMDevices\Audio\Render\*\Applications\* and the modern per-app policy store at
HKCU:\Software\Microsoft\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore
for anything referencing StarCraft after muting/unmuting a real session -- found nothing
in either, across 286 policy-store entries). That is not an exhaustive proof, so
Set-ScProcessMuted is called with -Mute $false explicitly wherever an audible launch is
requested (see run-with-plugin.ps1's -Sound handling) rather than simply skipped -- cheap
insurance against a persistence path this search did not find.

Dot-source this file; it defines Set-ScProcessMuted in the caller's scope.
#>

if (-not ('ScAudio.Interop' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace ScAudio {
  internal enum EDataFlow { eRender = 0 }
  internal enum ERole { eConsole = 0 }

  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(EDataFlow dataFlow, int stateMask, out IMMDeviceCollection ppDevices);
    int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppDevice);
  }

  [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IMMDeviceCollection {
    int GetCount(out uint count);
    int Item(uint index, out IMMDevice device);
  }

  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IMMDevice {
    int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams,
                 [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
  }

  // IAudioSessionManager2 : IAudioSessionManager -- the two base methods are stubbed
  // (never called) purely to keep GetSessionEnumerator at its real vtable slot.
  [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IAudioSessionManager2 {
    int GetAudioSessionControl(IntPtr sessionGuid, int streamFlags, out IntPtr control);
    int GetSimpleAudioVolume(IntPtr sessionGuid, int streamFlags, out IntPtr volume);
    int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnum);
  }

  [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IAudioSessionEnumerator {
    int GetCount(out int count);
    int GetSession(int index, out IAudioSessionControl session);
  }

  // A COM handle only -- every real call goes through .NET's automatic QueryInterface
  // when this is cast to IAudioSessionControl2 / ISimpleAudioVolume below, so its own
  // vtable shape (real interface has 9 methods) does not need to be declared here.
  [ComImport, Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IAudioSessionControl { }

  // IAudioSessionControl2 : IAudioSessionControl -- the 9 base methods are stubbed so
  // GetProcessId lands at its real vtable slot (the 3rd of this interface's own 5).
  [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IAudioSessionControl2 {
    int GetState(out int state);
    int GetDisplayName(out IntPtr name);
    int SetDisplayName(IntPtr name, ref Guid ctx);
    int GetIconPath(out IntPtr path);
    int SetIconPath(IntPtr path, ref Guid ctx);
    int GetGroupingParam(out Guid group);
    int SetGroupingParam(ref Guid group, ref Guid ctx);
    int RegisterAudioSessionNotification(IntPtr client);
    int UnregisterAudioSessionNotification(IntPtr client);
    int GetSessionIdentifier(out IntPtr id);
    int GetSessionInstanceIdentifier(out IntPtr id);
    [PreserveSig] int GetProcessId(out uint pid);
  }

  [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface ISimpleAudioVolume {
    int SetMasterVolume(float level, ref Guid ctx);
    int GetMasterVolume(out float level);
    [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx);
    [PreserveSig] int GetMute(out bool mute);
  }

  public static class Interop {
    private static readonly Guid CLSID_MMDeviceEnumerator = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
    private static readonly Guid IID_IAudioSessionManager2 = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
    private const int DEVICE_STATE_ACTIVE = 0x1;

    // Finds every active session for `pid`, across EVERY active render endpoint (not
    // just the default one -- see .DESCRIPTION for why that distinction is the whole
    // fix), and sets its mute state. Returns true iff at least one matching session was
    // found on any endpoint -- false means "no session found on any active endpoint",
    // not an error; the caller polls.
    public static bool TryMuteProcess(uint pid, bool mute) {
      var enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(Type.GetTypeFromCLSID(CLSID_MMDeviceEnumerator));
      IMMDeviceCollection collection;
      if (enumerator.EnumAudioEndpoints(EDataFlow.eRender, DEVICE_STATE_ACTIVE, out collection) != 0 || collection == null) return false;

      uint deviceCount;
      if (collection.GetCount(out deviceCount) != 0) return false;

      bool found = false;
      for (uint di = 0; di < deviceCount; di++) {
        IMMDevice device;
        if (collection.Item(di, out device) != 0 || device == null) continue;

        object sessionManagerObj;
        Guid iid = IID_IAudioSessionManager2;
        if (device.Activate(ref iid, 1 /* CLSCTX_INPROC_SERVER */, IntPtr.Zero, out sessionManagerObj) != 0) continue;
        var sessionManager = (IAudioSessionManager2)sessionManagerObj;

        IAudioSessionEnumerator sessionEnum;
        if (sessionManager.GetSessionEnumerator(out sessionEnum) != 0) continue;

        int count;
        sessionEnum.GetCount(out count);
        for (int i = 0; i < count; i++) {
          IAudioSessionControl ctrl;
          if (sessionEnum.GetSession(i, out ctrl) != 0 || ctrl == null) continue;
          var ctrl2 = ctrl as IAudioSessionControl2;
          if (ctrl2 == null) continue;
          uint sessionPid;
          if (ctrl2.GetProcessId(out sessionPid) != 0) continue;
          if (sessionPid != pid) continue;
          var vol = ctrl as ISimpleAudioVolume;
          if (vol == null) continue;
          Guid ctx = Guid.Empty;
          vol.SetMute(mute, ref ctx);
          found = true;
        }
      }
      return found;
    }
  }
}
"@
}

function Set-ScProcessMuted {
    <#
    .SYNOPSIS
    Set (or clear) the mute state of a process's own Windows audio session, across every
    active render endpoint. Polls for -TimeoutSec because the session does not
    necessarily exist the instant the process does.
    .DESCRIPTION
    Returns $true once a session for -ProcessId was found (on any active endpoint) and
    set to -Mute, $false if none appeared within -TimeoutSec. A $false is NOT treated as
    a fatal error by the caller -- some launches may take longer than the default timeout
    to create a session, or in principle never create one; the launch itself must not
    fail just because muting could not be confirmed.

    Does NOT keep checking after -TimeoutSec elapses -- see this file's top-of-file
    .DESCRIPTION for why an earlier background-re-check design was removed rather than
    kept as a mechanism that did not actually run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [bool]$Mute = $true,
        [int]$TimeoutSec = 15,
        [int]$PollMs = 300
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ([ScAudio.Interop]::TryMuteProcess([uint32]$ProcessId, $Mute)) { return $true }
        Start-Sleep -Milliseconds $PollMs
    }
    return $false
}
