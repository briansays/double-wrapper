<#
    double-wrap.ps1 — Create a double-password-protected zip (zip-in-zip).

    Usage: .\double-wrap.ps1 <target-path> [output-directory]

    <target-path> may be either a directory or a single file.

    Outputs (in output-directory, defaults to cwd):
      outer.zip   — the final double-wrapped archive
      inner.txt   — password for the inner zip
      outer.txt   — password for the outer zip
      log.txt     — full debug log with file/folder structure

    Requires 7-Zip (7z.exe) on PATH or installed in a standard location
    (C:\Program Files\7-Zip\7z.exe or C:\Program Files (x86)\7-Zip\7z.exe).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [Alias('TargetDirectory')]
    [string]$TargetPath,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$OutputDirectory = "."
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Logging setup

$script:LogFile = ""

function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    [Console]::Error.WriteLine($line)
    if ($script:LogFile -ne "") {
        Add-Content -LiteralPath $script:LogFile -Value $line
    }
}

function Write-Debug2 { param([string]$m) Write-Log -Level 'debug' -Message $m }
function Write-Info   { param([string]$m) Write-Log -Level 'info'  -Message $m }
function Write-Err    { param([string]$m) Write-Log -Level 'error' -Message $m }

# Password generation
# Generates a memorable passphrase-style password that satisfies these rules:
#   - at least 14 characters (max 24 to stay memorable)
#   - at least 2 digits
#   - at least 2 special characters
#   - at least 1 uppercase and 1 lowercase letter
#
# Strategy: pick 3 dictionary words, capitalize one, then splice in 2 digits
# and 2 symbols at varied positions.  Result looks like:
#   oak7#Breeze!cup4   (16 chars)
#   Mint&river38$fox   (16 chars)

# Cryptographically secure random integer in [0, n).
# Uses the OS CSPRNG via RandomNumberGenerator with rejection sampling to
# avoid modulo bias.  Works on both Windows PowerShell 5.1 and PowerShell 7.
$script:Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

function Get-SecureRandom {
    param([Parameter(Mandatory = $true)][int]$Max)
    $range = [uint64]4294967296                 # 2^32
    $limit = $range - ($range % [uint64]$Max)
    $bytes = New-Object byte[] 4
    while ($true) {
        $script:Rng.GetBytes($bytes)
        $r = [uint64][BitConverter]::ToUInt32($bytes, 0)
        if ($r -lt $limit) { return [int]($r % [uint64]$Max) }
    }
}

function Get-SecureItem {
    param([Parameter(Mandatory = $true)][object[]]$Items)
    return $Items[(Get-SecureRandom -Max $Items.Count)]
}

function New-Password {
    # Small curated word list — short, common, easy to remember
    $words = @(
        'ace','age','air','amp','ant','arc','ash','axe','bay','bed','bog','bow','bud','bug',
        'cab','cap','cat','cob','cod','cog','cow','cub','cup','cut','dew','dig','dim','dip',
        'dot','dry','dug','dye','ear','eel','egg','elk','elm','emu','end','era','eve','ewe',
        'fan','fig','fin','fir','fit','fix','fly','fog','fox','fry','fun','fur','gag','gap',
        'gem','gin','gnu','gum','gut','gym','hag','ham','hat','hay','hen','hex','hid','hike',
        'hill','hog','hop','hot','hub','hue','hug','hum','hut','ice','imp','ink','inn','ion',
        'ivy','jab','jag','jam','jar','jaw','jay','jet','jig','job','jog','joy','jug','jut',
        'keg','key','kid','kin','kit','lab','lad','lag','lap','law','lay','leg','lid','lip',
        'log','lot','low','lug','mad','map','mat','mew','mid','mix','mob','mop','mud','mug',
        'nab','nag','nap','net','new','nip','nod','nor','not','now','nut','oak','oar','oat',
        'odd','ode','off','oil','old','one','opt','orb','ore','our','out','owl','own','pad',
        'pal','pan','paw','pea','peg','pen','pet','pie','pig','pin','pit','ply','pod','pop',
        'pot','pry','pub','pug','pun','pup','put','rag','ram','ran','rap','rat','raw','ray',
        'red','rib','rid','rig','rim','rip','rob','rod','rot','row','rub','rug','rum','run',
        'rut','rye','sad','sag','sap','sat','saw','say','sea','set','shy','sip','sit','six',
        'ski','sky','sly','sob','sod','son','sop','sow','spy','sty','sub','sud','sum','sun',
        'tab','tag','tan','tap','tar','tax','ten','the','tie','tin','tip','toe','ton','too',
        'top','tow','toy','try','tub','tug','two','urn','use','van','vat','vet','vex','vie',
        'vow','wad','wag','war','wax','way','web','wed','wet','wig','win','wit','woe','wok',
        'won','woo','yak','yam','yap','yaw','yew','zen','zip','zoo',
        'bark','beam','bind','blue','bolt','bone','book','born','brim','cape','card',
        'cave','clip','coal','cone','cook','cool','core','cork','cove','crew','cube',
        'dare','dawn','deer','dome','dose','dove','draw','drum','duck','dune','dusk',
        'dust','echo','edge','fawn','fern','fire','fish','fist','flap','flaw','flex',
        'flip','foam','fold','font','fork','frog','fuel','gale','gate','glow','gold',
        'grip','gulf','gust','hail','hare','hawk','haze','heal','heat','helm','herd',
        'hike','hill','hint','hive','home','hood','hook','hope','horn','hose','jade',
        'jazz','joke','jump','keen','kite','knot','lace','lake','lamp','land','lark',
        'lava','lawn','leaf','lime','line','link','lion','loft','loom','loop','lore',
        'luck','lure','lynx','mane','mare','mask','maze','meal','melt','mesa','mink',
        'mint','moat','moon','moss','muse','nail','nest','node','note','opal','orca',
        'oval','pace','palm','path','peak','pear','pine','plum','pond','pool','prey',
        'prop','pulse','pump','quay','rain','reed','reef','rein','ride','ring','rise',
        'road','roam','rock','roof','rope','rose','rune','rush','sage','sail','salt',
        'sand','seal','seed','silk','sink','soar','soil','song','spin','star','stem',
        'stir','stow','surf','swan','tale','tank','tarn','teal','tide','tilt','tone',
        'tray','tree','trim','tune','vale','veil','vine','void','wade','wake','wand',
        'ward','wave','weld','west','wick','wild','wind','wine','wing','wish','wolf',
        'wood','wren','yarn','yoke','zeal','zinc','zone',
        'mountain','river','crystal','beneath','hollow','wander',
        'frozen','silk','meadow','thunder','orchid','brave',
        'chimney','puzzle','drifting','velvet','harbor','stone',
        'galaxy','whisper','cactus','nominal','lumber','frail',
        'spectrum','candle','rooftop','blizzard','falcon','dawn',
        'maple','journey','oxygen','carpet','shrine','noble',
        'lantern','cobalt','shadow','prism','delta','quirky',
        'anchor','feather','mosaic','tunnel','bronze','ember',
        'violin','glacier','pebble','scarlet','zenith','coral',
        'horizon','plume','wicker','fossil','nimble','spark',
        'riddle','typhoon','amber','gazelle','plaster','ivory',
        'clover','beacon','marbled','furnace','tundra','sable',
        'oyster','pillar','dusk','raven','flicker','opal',
        'compass','vintage','crescent','molten','drizzle','sage',
        'willow','breeze','parcel','summit','quartz','igloo',
        'penguin','trophy','nectar','bonfire','gadget','twist',
        'ripple','vertex','plume','thicket','azure','fossil',
        'acorn','badger','bamboo','banjo','barley','basin','bison','blossom','boulder','bramble',
        'buckle','burrow','cabin','canyon','caramel','cedar','cello','cherry','cinder','citrus',
        'comet','copper','cotton','cricket','cypress','dahlia','dolphin','domino','dragon','fennel',
        'fiddle','firefly','fjord','flannel','flint','garnet','ginger','granite','gravel','griffin',
        'hammock','hazel','heron','hickory','honey','indigo','iris','jasmine','jigsaw','juniper',
        'kayak','kernel','kettle','koala','ladder','lagoon','lemon','lily','linen','locket',
        'magnet','mango','marble','marlin','meteor','monsoon','muffin','mustang','nutmeg','octave',
        'olive','orbit','otter','paddle','panther','papaya','parrot','pepper','pigeon','pilot',
        'planet','pocket','poppy','pretzel','pumpkin','quill','quiver','rabbit','radish','rapids',
        'rocket','saddle','saffron','salmon','satchel','sequoia','sierra','sparrow','spruce','squirrel'
    )
    $symbols = @('!','@','#','$','%','&','*','?','+','=','^','~','-','_')

    $minLen = 14
    $maxLen = 24

    while ($true) {
        # Pick 3 random words
        $w1 = Get-SecureItem -Items $words
        $w2 = Get-SecureItem -Items $words
        $w3 = Get-SecureItem -Items $words

        # Capitalize one word at random
        $pick = Get-SecureRandom -Max 3
        switch ($pick) {
            0 { $w1 = $w1.Substring(0,1).ToUpper() + $w1.Substring(1) }
            1 { $w2 = $w2.Substring(0,1).ToUpper() + $w2.Substring(1) }
            2 { $w3 = $w3.Substring(0,1).ToUpper() + $w3.Substring(1) }
        }

        # Two separate digits and two symbols
        $d1 = Get-SecureRandom -Max 10
        $d2 = Get-SecureRandom -Max 10
        $s1 = Get-SecureItem -Items $symbols
        $s2 = Get-SecureItem -Items $symbols

        # Assemble — vary where digits and symbols land
        $pattern = Get-SecureRandom -Max 6
        switch ($pattern) {
            0 { $pw = "$w1$d1$s1$w2$s2$w3$d2" }
            1 { $pw = "$w1$s1$w2$d1$d2$s2$w3" }
            2 { $pw = "$d1$w1$s1$w2$s2$d2$w3" }
            3 { $pw = "$w1$s1$d1$w2$d2$s2$w3" }
            4 { $pw = "$w1$d1$w2$s1$s2$w3$d2" }
            5 { $pw = "$s1$w1$d1$d2$w2$w3$s2" }
        }

        # Enforce the rules explicitly
        $len = $pw.Length
        if ($len -lt $minLen -or $len -gt $maxLen) { continue }

        $digitCount   = ($pw -replace '[^0-9]', '').Length
        $specialCount = ($pw -replace '[A-Za-z0-9]', '').Length
        if ($digitCount -lt 2)        { continue }
        if ($specialCount -lt 2)      { continue }
        if ($pw -cnotmatch '[a-z]')   { continue }
        if ($pw -cnotmatch '[A-Z]')   { continue }

        return $pw
    }
}

# Locate 7-Zip
function Resolve-SevenZip {
    $cmd = Get-Command '7z.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command '7z' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

# Validation

try {
    $Target = (Resolve-Path -LiteralPath $TargetPath -ErrorAction Stop).Path
} catch {
    [Console]::Error.WriteLine("Target does not exist: $TargetPath")
    exit 1
}

if (Test-Path -LiteralPath $Target -PathType Container) {
    $TargetKind = 'dir'
} elseif (Test-Path -LiteralPath $Target -PathType Leaf) {
    $TargetKind = 'file'
} else {
    [Console]::Error.WriteLine("Target must be a regular file or directory: $Target")
    exit 1
}

$TargetName   = Split-Path -Path $Target -Leaf
$TargetParent = Split-Path -Path $Target -Parent

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$OutputDir = (Resolve-Path -LiteralPath $OutputDirectory).Path

$script:LogFile = Join-Path $OutputDir 'log.txt'
Set-Content -LiteralPath $script:LogFile -Value '' -NoNewline   # truncate / create

Write-Info  "========================================"
Write-Info  "double-wrap is starting"
Write-Info  "========================================"
Write-Debug2 "Target path      : $Target"
Write-Debug2 "Target kind      : $TargetKind"
Write-Debug2 "Output directory : $OutputDir"
Write-Debug2 "Script PID       : $PID"
Write-Debug2 "Shell            : PowerShell $($PSVersionTable.PSVersion)"
Write-Debug2 "Date             : $(Get-Date)"
Write-Debug2 "Hostname         : $([System.Net.Dns]::GetHostName())"
Write-Debug2 "User             : $env:USERNAME"

# Check 7-Zip is available
$SevenZip = Resolve-SevenZip
if (-not $SevenZip) {
    Write-Err "'7z.exe' not found. Install 7-Zip first (https://www.7-zip.org/) and ensure it is on PATH."
    exit 1
}
Write-Debug2 "7-Zip binary     : $SevenZip"

# File/folder structure listing
if ($TargetKind -eq 'dir') {
    Write-Info "Recording file/folder structure of target directory..."
    Write-Debug2 "--- BEGIN STRUCTURE ---"
    # Skip dotfiles/dot-directories to match `find ... -not -path '*/\.*'`
    $allEntries = Get-ChildItem -LiteralPath $Target -Recurse -Force |
        Where-Object { ($_.FullName.Substring($Target.Length) -split '[\\/]') -notmatch '^\.' }
    $structureLines = @($Target) + ($allEntries | ForEach-Object { $_.FullName }) | Sort-Object
    foreach ($line in $structureLines) {
        Write-Debug2 "  $line"
    }
    Write-Debug2 "--- END STRUCTURE ---"

    $files = @(Get-ChildItem -LiteralPath $Target -Recurse -File -Force)
    $dirs  = @(Get-ChildItem -LiteralPath $Target -Recurse -Directory -Force)
    $FileCount = $files.Count
    $DirCount  = $dirs.Count + 1  # include the target dir itself, matching `find -type d`
    $TotalSize = ($files | Measure-Object -Property Length -Sum).Sum
    if (-not $TotalSize) { $TotalSize = 0 }
    Write-Debug2 "Total files       : $FileCount"
    Write-Debug2 "Total directories : $DirCount"
    Write-Debug2 "Total size (bytes): $TotalSize"
} else {
    Write-Info "Recording target file metadata..."
    $TotalSize = (Get-Item -LiteralPath $Target).Length
    Write-Debug2 "Target file       : $TargetName"
    Write-Debug2 "Total size (bytes): $TotalSize"
}

# Generate passwords

Write-Info "Generating passwords..."
$InnerPass = New-Password
$OuterPass = New-Password
Write-Debug2 "Inner password generated ($($InnerPass.Length) chars)"
Write-Debug2 "Outer password generated ($($OuterPass.Length) chars)"

# Temp workspace

$WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $WorkDir | Out-Null
Write-Debug2 "Temp workspace    : $WorkDir"

$cleanup = {
    if (Test-Path -LiteralPath $WorkDir) {
        Write-Debug2 "Cleaning up temp workspace: $WorkDir"
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Debug2 "Cleanup complete"
    }
}

try {
    # Inner zip

    $InnerZip = Join-Path $WorkDir 'inner.zip'

    Write-Info "Creating inner zip (password-protected)..."
    Write-Debug2 "Inner zip path    : $InnerZip"
    Write-Debug2 "Archiving ${TargetKind}: $TargetName"

    Push-Location -LiteralPath $TargetParent
    try {
        if ($TargetKind -eq 'dir') {
            $innerArgs = @('a', '-tzip', "-p$InnerPass", '-r', $InnerZip, $TargetName)
        } else {
            $innerArgs = @('a', '-tzip', "-p$InnerPass", $InnerZip, $TargetName)
        }
        $innerOutput = & $SevenZip @innerArgs 2>&1
        $innerExit = $LASTEXITCODE
        foreach ($line in $innerOutput) {
            Write-Debug2 "[zip-inner] $line"
        }
        if ($innerExit -ne 0) {
            Write-Err "Inner zip failed with exit code $innerExit"
            exit 1
        }
    } finally {
        Pop-Location
    }

    $InnerSize = (Get-Item -LiteralPath $InnerZip).Length
    Write-Debug2 "Inner zip size    : $InnerSize bytes"
    Write-Info "Inner zip created successfully"

    # Outer zip

    $OuterZip = Join-Path $OutputDir 'outer.zip'
    if (Test-Path -LiteralPath $OuterZip) {
        Remove-Item -LiteralPath $OuterZip -Force
    }

    Write-Info "Creating outer zip (password-protected, wrapping inner zip)..."
    Write-Debug2 "Outer zip path    : $OuterZip"

    Push-Location -LiteralPath $WorkDir
    try {
        $outerArgs = @('a', '-tzip', "-p$OuterPass", $OuterZip, 'inner.zip')
        $outerOutput = & $SevenZip @outerArgs 2>&1
        $outerExit = $LASTEXITCODE
        foreach ($line in $outerOutput) {
            Write-Debug2 "[zip-outer] $line"
        }
        if ($outerExit -ne 0) {
            Write-Err "Outer zip failed with exit code $outerExit"
            exit 1
        }
    } finally {
        Pop-Location
    }

    $OuterSize = (Get-Item -LiteralPath $OuterZip).Length
    Write-Debug2 "Outer zip size    : $OuterSize bytes"
    Write-Info "Outer zip created successfully"

    # Write password files

    Write-Info "Writing password files..."
    $InnerPwPath = Join-Path $OutputDir 'inner.txt'
    $OuterPwPath = Join-Path $OutputDir 'outer.txt'
    Set-Content -LiteralPath $InnerPwPath -Value $InnerPass
    Write-Debug2 "Wrote inner password to: $InnerPwPath"
    Set-Content -LiteralPath $OuterPwPath -Value $OuterPass
    Write-Debug2 "Wrote outer password to: $OuterPwPath"

    # Summary

    Write-Info "========================================"
    Write-Info "DONE — Summary"
    Write-Info "========================================"
    Write-Info "  Archive  : $OuterZip"
    Write-Info "  Inner pw : $InnerPwPath"
    Write-Info "  Outer pw : $OuterPwPath"
    Write-Info "  Log      : $script:LogFile"
    Write-Info ""
    Write-Info "To extract:"
    Write-Info "  1. 7z x -p`"`$(Get-Content outer.txt)`" outer.zip"
    Write-Info "  2. 7z x -p`"`$(Get-Content inner.txt)`" inner.zip"
    Write-Info "========================================"
}
finally {
    & $cleanup
}
