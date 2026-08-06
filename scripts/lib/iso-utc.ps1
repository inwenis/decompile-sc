# Shared ISO-8601 -> Kind=Utc [DateTime] parser (task 097). Every reader that
# compares a stamped timestamp (status.json's updatedAt, a message's sent:
# front-matter, ...) against [DateTime]::UtcNow must go through this instead
# of rolling its own [DateTime]::Parse -- see the bug below.
#
# ROOT CAUSE this fixes: `ConvertFrom-Json` already auto-coerces a
# recognizable ISO string property into a [DateTime] (Kind=Utc for a
# `Z`-suffixed value, holding the correct instant). Re-running that DateTime
# through `[DateTime]::Parse($value)` stringifies it first via the
# PowerShell-to-.NET binder's implicit ToString() -- which drops the zone
# marker -- then re-parses that zone-less string under the CURRENT CULTURE as
# Kind=Unspecified. A later `.ToUniversalTime()` then treats that Unspecified
# value as local wall time and subtracts the local UTC offset AGAIN, doubling
# it. Accepting the already-parsed [DateTime] here (instead of forcing it back
# through string parsing) is what avoids the double conversion.

function ConvertFrom-IsoUtc {
    # $Value is whatever a caller already has in hand: a raw ISO-8601 string
    # (message front-matter, a hand-built payload) OR a [DateTime] that
    # ConvertFrom-Json already produced from one. Both paths return Kind=Utc.
    param([Parameter(Mandatory)]$Value)

    if ($Value -is [DateTime]) {
        switch ($Value.Kind) {
            'Utc' { return $Value }
            'Local' { return $Value.ToUniversalTime() }
            # Unspecified only happens for a naive (no Z/offset) source string
            # -- this codebase's convention is that a naive timestamp is
            # already UTC wall time, so label it rather than convert it.
            default { return [DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc) }
        }
    }

    $dt = [DateTime]::Parse(
        [string]$Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind)
    switch ($dt.Kind) {
        'Utc' { return $dt }
        'Local' { return $dt.ToUniversalTime() }
        default { return [DateTime]::SpecifyKind($dt, [DateTimeKind]::Utc) }
    }
}
