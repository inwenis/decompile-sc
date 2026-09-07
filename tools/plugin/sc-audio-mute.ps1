<#
.SYNOPSIS
Process-scoped audio mute via Windows Core Audio (WASAPI) session volume, so unattended
launches are silent by default -- no registry, no file, no state outliving the target
process. Dot-source this file; it defines Set-ScProcessMuted in the caller's scope.
.DESCRIPTION
Never mute through the game's own HKCU registry volume settings: that state outlives the
process and overwrites the user's real audio settings.
Enumerate EVERY active render endpoint (EnumAudioEndpoints, DEVICE_STATE_ACTIVE), not just the
default: StarCraft has been seen holding sessions on three distinct endpoints of one machine
(line-out, HDMI, USB), so a default-only search finds nothing while a live session sits elsewhere.
Match sessions by process id, not by name: by name resolves to whichever StarCraft is running.
A search of both per-app audio policy stores (286 entries) found nothing SetMute writes; that is
not exhaustive proof, so an audible launch passes -Mute $false explicitly (run-with-plugin.ps1).
#>

if (-not ('ScAudio.Interop' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace ScAudio {
  internal enum EDataFlow { eRender = 0 }
  internal enum ERole { eConsole = 0 }

  // [PreserveSig] on every method in every interface below, without exception. Without
  // it the CLR treats the int return as an HRESULT and THROWS on any failure code
  // instead of returning it -- silently turning every `if (... != 0) return false` /
  // `continue` guard in TryMuteProcess into dead code. A verifier proved this live:
  // IMMDeviceCollection.Item(9999) (an out-of-range index) threw ArgumentException
  // instead of returning a failure HRESULT, because Item lacked [PreserveSig]. The
  // failure mode that matters here: an endpoint invalidated mid-enumeration (a USB
  // headset unplugged, an HDMI monitor sleeping -- both device classes are real
  // possibilities, not theoretical) would throw an uncaught exception out of a launch
  // script well after the game is already up and running.
  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IMMDeviceEnumerator {
    [PreserveSig] int EnumAudioEndpoints(EDataFlow dataFlow, int stateMask, out IMMDeviceCollection ppDevices);
    [PreserveSig] int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppDevice);
  }

  [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IMMDeviceCollection {
    [PreserveSig] int GetCount(out uint count);
    [PreserveSig] int Item(uint index, out IMMDevice device);
  }

  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IMMDevice {
    [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams,
                 [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
  }

  // IAudioSessionManager2 : IAudioSessionManager -- the two base methods are stubbed
  // (never called) purely to keep GetSessionEnumerator at its real vtable slot.
  [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IAudioSessionManager2 {
    [PreserveSig] int GetAudioSessionControl(IntPtr sessionGuid, int streamFlags, out IntPtr control);
    [PreserveSig] int GetSimpleAudioVolume(IntPtr sessionGuid, int streamFlags, out IntPtr volume);
    [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnum);
  }

  [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IAudioSessionEnumerator {
    [PreserveSig] int GetCount(out int count);
    [PreserveSig] int GetSession(int index, out IAudioSessionControl session);
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
    [PreserveSig] int GetState(out int state);
    [PreserveSig] int GetDisplayName(out IntPtr name);
    [PreserveSig] int SetDisplayName(IntPtr name, ref Guid ctx);
    [PreserveSig] int GetIconPath(out IntPtr path);
    [PreserveSig] int SetIconPath(IntPtr path, ref Guid ctx);
    [PreserveSig] int GetGroupingParam(out Guid group);
    [PreserveSig] int SetGroupingParam(ref Guid group, ref Guid ctx);
    [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
    [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
    [PreserveSig] int GetSessionIdentifier(out IntPtr id);
    [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
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
    Returns $true once a session for -ProcessId was found and set to -Mute, $false if none
    appeared within -TimeoutSec. $false is not fatal to the caller: a launch must not fail
    because muting could not be confirmed, so past the timeout the launch continues audible.
    Do not add a background timer to keep re-affirming the mute: a Register-ObjectEvent timer
    does not fire while the caller sits inside Start-Sleep (0 ticks measured across a 3s
    sleep), which is most of what scripts and suites do, and it dies with the calling pwsh.
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
