<#
    double-wrap.ps1 — Create a double-password-protected zip (zip-in-zip).

    Usage: .\double-wrap.ps1 <target-directory> [output-directory]

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
    [string]$TargetDirectory,

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
# Generates a memorable passphrase-style password (14-20 chars) that includes
# lowercase, uppercase, digits, and symbols.
#
# Strategy: pick 2-3 short dictionary words, capitalize one, insert a digit
# group and a symbol to glue them together.  Result looks like:
#   oak7#Breeze!cup   (17 chars)
#   Mint3&river$fox   (15 chars)

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
        'ripple','vertex','plume','thicket','azure','fossil'
    )
    $symbols = @('!','@','#','$','%','&','*','?','+','=')

    while ($true) {
        # Pick 3 random words
        $w1 = Get-Random -InputObject $words
        $w2 = Get-Random -InputObject $words
        $w3 = Get-Random -InputObject $words

        # Capitalize one word at random
        $pick = Get-Random -Minimum 0 -Maximum 3
        switch ($pick) {
            0 { $w1 = $w1.Substring(0,1).ToUpper() + $w1.Substring(1) }
            1 { $w2 = $w2.Substring(0,1).ToUpper() + $w2.Substring(1) }
            2 { $w3 = $w3.Substring(0,1).ToUpper() + $w3.Substring(1) }
        }

        # Random digit(s) and symbol
        $digit = Get-Random -Minimum 0 -Maximum 100
        $sym   = Get-Random -InputObject $symbols
        $sym2  = Get-Random -InputObject $symbols

        # Assemble — vary the pattern
        $pattern = Get-Random -Minimum 0 -Maximum 4
        switch ($pattern) {
            0 { $pw = "$w1$digit$sym$w2$sym2$w3" }
            1 { $pw = "$w1$sym$w2$digit$sym2$w3" }
            2 { $pw = "$w1$sym$digit$w2$sym2$w3" }
            3 { $pw = "$w1$sym$w2$sym2$w3$digit" }
        }

        $len = $pw.Length
        if ($len -ge 14 -and $len -le 20) {
            # Verify complexity: has lower, upper, digit, symbol
            if ($pw -cmatch '[a-z]' -and $pw -cmatch '[A-Z]' -and `
                $pw -match '[0-9]' -and $pw -match '[!@#\$%&\*\?\+=]') {
                return $pw
            }
        }
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
    $TargetDir = (Resolve-Path -LiteralPath $TargetDirectory -ErrorAction Stop).Path
} catch {
    [Console]::Error.WriteLine("Target directory does not exist: $TargetDirectory")
    exit 1
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$OutputDir = (Resolve-Path -LiteralPath $OutputDirectory).Path

$script:LogFile = Join-Path $OutputDir 'log.txt'
Set-Content -LiteralPath $script:LogFile -Value '' -NoNewline   # truncate / create

Write-Info  "========================================"
Write-Info  "double-wrap is starting"
Write-Info  "========================================"
Write-Debug2 "Target directory : $TargetDir"
Write-Debug2 "Output directory : $OutputDir"
Write-Debug2 "Script PID       : $PID"
Write-Debug2 "Shell            : PowerShell $($PSVersionTable.PSVersion)"
Write-Debug2 "Date             : $(Get-Date)"
Write-Debug2 "Hostname         : $([System.Net.Dns]::GetHostName())"
Write-Debug2 "User             : $env:USERNAME"

# Check target exists (and is a directory)
if (-not (Test-Path -LiteralPath $TargetDir -PathType Container)) {
    Write-Err "Target directory does not exist: $TargetDir"
    exit 1
}

# Check 7-Zip is available
$SevenZip = Resolve-SevenZip
if (-not $SevenZip) {
    Write-Err "'7z.exe' not found. Install 7-Zip first (https://www.7-zip.org/) and ensure it is on PATH."
    exit 1
}
Write-Debug2 "7-Zip binary     : $SevenZip"

# File/folder structure listing
Write-Info "Recording file/folder structure of target directory..."
Write-Debug2 "--- BEGIN STRUCTURE ---"
# Skip dotfiles/dot-directories to match `find ... -not -path '*/\.*'`
$allEntries = Get-ChildItem -LiteralPath $TargetDir -Recurse -Force |
    Where-Object { ($_.FullName.Substring($TargetDir.Length) -split '[\\/]') -notmatch '^\.' }
$structureLines = @($TargetDir) + ($allEntries | ForEach-Object { $_.FullName }) | Sort-Object
foreach ($line in $structureLines) {
    Write-Debug2 "  $line"
}
Write-Debug2 "--- END STRUCTURE ---"

# File count & total size
$files = Get-ChildItem -LiteralPath $TargetDir -Recurse -File -Force
$dirs  = Get-ChildItem -LiteralPath $TargetDir -Recurse -Directory -Force
$FileCount = $files.Count
$DirCount  = $dirs.Count + 1  # include the target dir itself, matching `find -type d`
$TotalSize = ($files | Measure-Object -Property Length -Sum).Sum
if (-not $TotalSize) { $TotalSize = 0 }
Write-Debug2 "Total files       : $FileCount"
Write-Debug2 "Total directories : $DirCount"
Write-Debug2 "Total size (bytes): $TotalSize"

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
    $DirName  = Split-Path -Path $TargetDir -Leaf
    $ParentDir = Split-Path -Path $TargetDir -Parent

    Write-Info "Creating inner zip (password-protected)..."
    Write-Debug2 "Inner zip path    : $InnerZip"
    Write-Debug2 "Archiving directory basename: $DirName"

    Push-Location -LiteralPath $ParentDir
    try {
        $innerArgs = @('a', '-tzip', "-p$InnerPass", '-r', $InnerZip, $DirName)
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
