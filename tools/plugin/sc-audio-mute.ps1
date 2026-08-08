<#
.SYNOPSIS
Process-scoped audio mute via Windows Core Audio (WASAPI) session volume -- no registry,
no file, no state that outlives the target process.

.DESCRIPTION
task018: unattended test launches must be silent by default; the first attempt at this
used the game's own HKCU registry volume settings (mute before launch, restore after) and
that went badly -- see tools/plugin/README.md "Sound" and the 2026-08-08 incident it
references. This is the replacement: mute the game's own per-application audio session
directly, the same mechanism the Windows Volume Mixer uses per-app. Nothing is written to
disk or the registry, there is nothing to restore, and the mute dies with the process --
a crash, a kill, or two overlapping runs cannot leave anything muted or corrupted, because
there is no persistent state to begin with.

Session enumeration walks every active session on the DEFAULT RENDER endpoint and matches
by process id (IAudioSessionControl2::GetProcessId), the same identification approach
check-game-windows.ps1 and close-game.ps1 already use for windows -- resolving "the game"
by name would hit whichever StarCraft happens to be running.

The game's audio session does not necessarily exist the instant the process does (its
sound engine initialises after the window comes up), so Set-ScProcessMuted polls for it.

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
    int EnumAudioEndpoints(EDataFlow dataFlow, int stateMask, out IntPtr ppDevices);
    int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppDevice);
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
    int GetMute(out bool mute);
  }

  public static class Interop {
    private static readonly Guid CLSID_MMDeviceEnumerator = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
    private static readonly Guid IID_IAudioSessionManager2 = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");

    // Finds the active session for `pid` on the default render endpoint and sets its
    // mute state. Returns true iff a matching session was found (mute was actually
    // applied) -- false means "no session yet", not an error; the caller polls.
    public static bool TryMuteProcess(uint pid, bool mute) {
      var enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(Type.GetTypeFromCLSID(CLSID_MMDeviceEnumerator));
      IMMDevice device;
      if (enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eConsole, out device) != 0 || device == null) return false;

      object sessionManagerObj;
      Guid iid = IID_IAudioSessionManager2;
      if (device.Activate(ref iid, 1 /* CLSCTX_INPROC_SERVER */, IntPtr.Zero, out sessionManagerObj) != 0) return false;
      var sessionManager = (IAudioSessionManager2)sessionManagerObj;

      IAudioSessionEnumerator sessionEnum;
      if (sessionManager.GetSessionEnumerator(out sessionEnum) != 0) return false;

      int count;
      sessionEnum.GetCount(out count);
      bool found = false;
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
      return found;
    }
  }
}
"@
}

function Set-ScProcessMuted {
    <#
    .SYNOPSIS
    Mute a process's own Windows audio session, and keep it muted for as long as the
    process and the calling PowerShell session both live.
    .DESCRIPTION
    Two parts, because the game's audio session is created LAZILY -- verified live:
    StarCraft sitting at its own main menu, visibly running (not stalled), still shows
    ZERO sessions in the enumerator until something actually plays a sound. The moment
    that first happens can be well after launch and well into a test run driving menus
    or gameplay, not just in the first few seconds.

    1. An immediate poll (-TimeoutSec/-PollMs) covers the common case -- a session that
       already exists, or appears within a few seconds -- and gives the caller a
       same-call true/false signal.
    2. A background System.Timers.Timer (via Register-ObjectEvent, so its callback runs
       on THIS runspace's own event queue rather than a foreign thread -- calling into
       PowerShell/.NET types from a raw thread-pool timer callback is not something this
       host does safely) re-affirms the mute every 1.5s, so whichever moment the session
       actually appears, it gets muted within about that long of existing. Self-cleaning:
       stops and unregisters itself once the process exits or -BackgroundMinutes elapses,
       whichever first -- nothing is left running past the game's own lifetime, and
       nothing can spin forever if a handle were somehow never released.

    ISimpleAudioVolume::SetMute is idempotent and process-scoped (see sc-audio-mute.ps1
    top-of-file .DESCRIPTION): re-affirming it on a timer costs nothing persistent and
    leaves nothing to clean up on exit, unlike the registry approach this replaced.

    Returns $true iff the immediate poll found and muted a session; $false only means
    "not found THAT fast" -- the background timer keeps trying regardless, so $false is
    not a fatal signal to the caller.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [bool]$Mute = $true,
        [int]$TimeoutSec = 8,
        [int]$PollMs = 300,
        [int]$BackgroundMinutes = 30
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $foundNow = $false
    while ((Get-Date) -lt $deadline) {
        if ([ScAudio.Interop]::TryMuteProcess([uint32]$ProcessId, $Mute)) { $foundNow = $true; break }
        Start-Sleep -Milliseconds $PollMs
    }

    if ($Mute) {
        $timer = New-Object System.Timers.Timer
        $timer.Interval = 1500
        $timer.AutoReset = $true
        $ctx = [pscustomobject]@{ ProcessId = $ProcessId; UntilUtc = [DateTime]::UtcNow.AddMinutes($BackgroundMinutes) }
        $subscriberName = "ScAudioMute_$ProcessId`_$([Guid]::NewGuid().ToString('N'))"
        $null = Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $subscriberName -MessageData $ctx -Action {
            $c = $Event.MessageData
            $stillRunning = Get-Process -Id $c.ProcessId -ErrorAction SilentlyContinue
            if (-not $stillRunning -or [DateTime]::UtcNow -ge $c.UntilUtc) {
                $Sender.Stop()
                $Sender.Dispose()
                Unregister-Event -SourceIdentifier $Event.SourceIdentifier -ErrorAction SilentlyContinue
                return
            }
            [ScAudio.Interop]::TryMuteProcess([uint32]$c.ProcessId, $true) | Out-Null
        }
        $timer.Start()
    }

    return $foundNow
}
