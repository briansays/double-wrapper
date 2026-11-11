#!/usr/bin/env bash
#
# double-wrap.sh — Create a double-password-protected zip (zip-in-zip).
#
# Usage: ./double-wrap.sh <target-path> [output-directory]
#
# <target-path> may be either a directory or a single file.
#
# Outputs (in output-directory, defaults to cwd):
#   outer.zip   — the final double-wrapped archive
#   inner.txt   — password for the inner zip
#   outer.txt   — password for the outer zip
#   log.txt     — full debug log with file/folder structure
#
set -euo pipefail

# Logging setup 

LOG_FILE=""

log() {
    local level="$1"; shift
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local msg="[$ts] [$level] $*"
    echo "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}

debug() { log "debug" "$@"; }
info()  { log "info" "$@"; }
error() { log "error" "$@"; }

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
# Reads 4 bytes from /dev/urandom and uses rejection sampling to avoid
# modulo bias.
secure_rand() {
    local n="$1" r
    local range=4294967296                      # 2^32
    local limit=$(( range - (range % n) ))
    while true; do
        r=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')
        if (( r < limit )); then
            echo $(( r % n ))
            return
        fi
    done
}

generate_password() {
    # Small curated word list — short, common, easy to remember
    local words=(
        ace age air amp ant arc ash axe bay bed bog bow bud bug
        cab cap cat cob cod cog cow cub cup cut dew dig dim dip
        dot dry dug dye ear eel egg elk elm emu end era eve ewe
        fan fig fin fir fit fix fly fog fox fry fun fur gag gap
        gem gin gnu gum gut gym hag ham hat hay hen hex hid hike
        hill hog hop hot hub hue hug hum hut ice imp ink inn ion
        ivy jab jag jam jar jaw jay jet jig job jog joy jug jut
        keg key kid kin kit lab lad lag lap law lay leg lid lip
        log lot low lug mad map mat mew mid mix mob mop mud mug
        nab nag nap net new nip nod nor not now nut oak oar oat
        odd ode off oil old one opt orb ore our out owl own pad
        pal pan paw pea peg pen pet pie pig pin pit ply pod pop
        pot pry pub pug pun pup put rag ram ran rap rat raw ray
        red rib rid rig rim rip rob rod rot row rub rug rum run
        rut rye sad sag sap sat saw say sea set shy sip sit six
        ski sky sly sob sod son sop sow spy sty sub sud sum sun
        tab tag tan tap tar tax ten the tie tin tip toe ton too
        top tow toy try tub tug two urn use van vat vet vex vie
        vow wad wag war wax way web wed wet wig win wit woe wok
        won woo yak yam yap yaw yew zen zip zoo
        bark beam bind blue bolt bone book born brim cape card
        cave clip coal cone cook cool core cork cove crew cube
        dare dawn deer dome dose dove draw drum duck dune dusk
        dust echo edge fawn fern fire fish fist flap flaw flex
        flip foam fold font fork frog fuel gale gate glow gold
        grip gulf gust hail hare hawk haze heal heat helm herd
        hike hill hint hive home hood hook hope horn hose jade
        jazz joke jump keen kite knot lace lake lamp land lark
        lava lawn leaf lime line link lion loft loom loop lore
        luck lure lynx mane mare mask maze meal melt mesa mink
        mint moat moon moss muse nail nest node note opal orca
        oval pace palm path peak pear pine plum pond pool prey
        prop pulse pump quay rain reed reef rein ride ring rise
        road roam rock roof rope rose rune rush sage sail salt
        sand seal seed silk sink soar soil song spin star stem
        stir stow surf swan tale tank tarn teal tide tilt tone
        tray tree trim tune vale veil vine void wade wake wand
        ward wave weld west wick wild wind wine wing wish wolf
        wood wren yarn yoke zeal zinc zone
        mountain river crystal beneath hollow wander
        frozen silk meadow thunder orchid brave
        chimney puzzle drifting velvet harbor stone
        galaxy whisper cactus nominal lumber frail
        spectrum candle rooftop blizzard falcon dawn
        maple journey oxygen carpet shrine noble
        lantern cobalt shadow prism delta quirky
        anchor feather mosaic tunnel bronze ember
        violin glacier pebble scarlet zenith coral
        horizon plume wicker fossil nimble spark
        riddle typhoon amber gazelle plaster ivory
        clover beacon marbled furnace tundra sable
        oyster pillar dusk raven flicker opal
        compass vintage crescent molten drizzle sage
        willow breeze parcel summit quartz igloo
        penguin trophy nectar bonfire gadget twist
        ripple vertex plume thicket azure fossil
        acorn badger bamboo banjo barley basin bison blossom boulder bramble
        buckle burrow cabin canyon caramel cedar cello cherry cinder citrus
        comet copper cotton cricket cypress dahlia dolphin domino dragon fennel
        fiddle firefly fjord flannel flint garnet ginger granite gravel griffin
        hammock hazel heron hickory honey indigo iris jasmine jigsaw juniper
        kayak kernel kettle koala ladder lagoon lemon lily linen locket
        magnet mango marble marlin meteor monsoon muffin mustang nutmeg octave
        olive orbit otter paddle panther papaya parrot pepper pigeon pilot
        planet pocket poppy pretzel pumpkin quill quiver rabbit radish rapids
        rocket saddle saffron salmon satchel sequoia sierra sparrow spruce squirrel
    )
    local symbols=('!' '@' '#' '$' '%' '&' '*' '?' '+' '=' '^' '~' '-' '_')

    local count=${#words[@]}
    local nsym=${#symbols[@]}
    local min_len=14 max_len=24
    local pw=""

    while true; do
        # Pick 3 random words
        local w1="${words[$(secure_rand "$count")]}"
        local w2="${words[$(secure_rand "$count")]}"
        local w3="${words[$(secure_rand "$count")]}"

        # Capitalize one word at random
        local pick=$(secure_rand 3)
        case $pick in
            0) w1="$(echo "${w1:0:1}" | tr '[:lower:]' '[:upper:]')${w1:1}" ;;
            1) w2="$(echo "${w2:0:1}" | tr '[:lower:]' '[:upper:]')${w2:1}" ;;
            2) w3="$(echo "${w3:0:1}" | tr '[:lower:]' '[:upper:]')${w3:1}" ;;
        esac

        # Two separate digits and two symbols
        local d1=$(secure_rand 10)
        local d2=$(secure_rand 10)
        local s1="${symbols[$(secure_rand "$nsym")]}"
        local s2="${symbols[$(secure_rand "$nsym")]}"

        # Assemble — vary where digits and symbols land
        local pattern=$(secure_rand 6)
        case $pattern in
            0) pw="${w1}${d1}${s1}${w2}${s2}${w3}${d2}" ;;
            1) pw="${w1}${s1}${w2}${d1}${d2}${s2}${w3}" ;;
            2) pw="${d1}${w1}${s1}${w2}${s2}${d2}${w3}" ;;
            3) pw="${w1}${s1}${d1}${w2}${d2}${s2}${w3}" ;;
            4) pw="${w1}${d1}${w2}${s1}${s2}${w3}${d2}" ;;
            5) pw="${s1}${w1}${d1}${d2}${w2}${w3}${s2}" ;;
        esac

        # Enforce the rules explicitly
        local len=${#pw}
        (( len >= min_len && len <= max_len )) || continue

        local digits="${pw//[^0-9]/}"
        local specials="${pw//[A-Za-z0-9]/}"
        (( ${#digits} >= 2 ))   || continue
        (( ${#specials} >= 2 )) || continue
        [[ "$pw" =~ [a-z] ]]    || continue
        [[ "$pw" =~ [A-Z] ]]    || continue

        echo "$pw"
        return
    done
}

# Validation 

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <target-path> [output-directory]" >&2
    exit 1
fi

if [[ ! -e "$1" ]]; then
    echo "Target does not exist: $1" >&2
    exit 1
fi

TARGET_PARENT="$(cd "$(dirname "$1")" && pwd)"
TARGET_NAME="$(basename "$1")"
TARGET="$TARGET_PARENT/$TARGET_NAME"

if [[ -d "$TARGET" ]]; then
    TARGET_KIND="dir"
elif [[ -f "$TARGET" ]]; then
    TARGET_KIND="file"
else
    echo "Target must be a regular file or directory: $TARGET" >&2
    exit 1
fi

OUTPUT_DIR="${2:-.}"
OUTPUT_DIR="$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)"

LOG_FILE="$OUTPUT_DIR/log.txt"
: > "$LOG_FILE"   # truncate / create

info "========================================"
info "double-wrap is starting"
info "========================================"
debug "Target path      : $TARGET"
debug "Target kind      : $TARGET_KIND"
debug "Output directory : $OUTPUT_DIR"
debug "Script PID       : $$"
debug "Shell            : $BASH_VERSION"
debug "Date             : $(date)"
debug "Hostname         : $(hostname)"
debug "User             : $(whoami)"

# Check zip is available
if ! command -v zip &>/dev/null; then
    error "'zip' command not found. Install it first (e.g. brew install zip)."
    exit 1
fi

# File/folder structure listing
if [[ "$TARGET_KIND" == "dir" ]]; then
    info "Recording file/folder structure of target directory..."
    debug "--- BEGIN STRUCTURE ---"
    while IFS= read -r line; do
        debug "  $line"
    done < <(find "$TARGET" -not -path '*/\.*' | sort)
    debug "--- END STRUCTURE ---"

    FILE_COUNT=$(find "$TARGET" -type f | wc -l | tr -d ' ')
    DIR_COUNT=$(find "$TARGET" -type d | wc -l | tr -d ' ')
    if stat --version &>/dev/null 2>&1; then
        TOTAL_SIZE=$(find "$TARGET" -type f -exec stat --printf='%s\n' {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
    else
        TOTAL_SIZE=$(find "$TARGET" -type f -exec stat -f'%z' {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
    fi
    debug "Total files       : $FILE_COUNT"
    debug "Total directories : $DIR_COUNT"
    debug "Total size (bytes): $TOTAL_SIZE"
else
    info "Recording target file metadata..."
    if stat --version &>/dev/null 2>&1; then
        TOTAL_SIZE=$(stat --printf='%s' "$TARGET")
    else
        TOTAL_SIZE=$(stat -f'%z' "$TARGET")
    fi
    debug "Target file       : $TARGET_NAME"
    debug "Total size (bytes): $TOTAL_SIZE"
fi

# Generate passwords 

info "Generating passwords..."
INNER_PASS="$(generate_password)"
OUTER_PASS="$(generate_password)"
debug "Inner password generated (${#INNER_PASS} chars)"
debug "Outer password generated (${#OUTER_PASS} chars)"

# Temp workspace

WORK_DIR="$(mktemp -d)"
debug "Temp workspace    : $WORK_DIR"
cleanup() {
    debug "Cleaning up temp workspace: $WORK_DIR"
    rm -rf "$WORK_DIR"
    debug "Cleanup complete"
}
trap cleanup EXIT

# Inner zip

INNER_ZIP="$WORK_DIR/inner.zip"

info "Creating inner zip (password-protected)..."
debug "Inner zip path    : $INNER_ZIP"
debug "Archiving $TARGET_KIND: $TARGET_NAME"

if [[ "$TARGET_KIND" == "dir" ]]; then
    (cd "$TARGET_PARENT" && zip -r -P "$INNER_PASS" "$INNER_ZIP" "$TARGET_NAME") 2>&1 | while IFS= read -r line; do
        debug "[zip-inner] $line"
    done
else
    (cd "$TARGET_PARENT" && zip -P "$INNER_PASS" "$INNER_ZIP" "$TARGET_NAME") 2>&1 | while IFS= read -r line; do
        debug "[zip-inner] $line"
    done
fi

INNER_SIZE=$(stat -f'%z' "$INNER_ZIP" 2>/dev/null || stat --printf='%s' "$INNER_ZIP" 2>/dev/null)
debug "Inner zip size    : $INNER_SIZE bytes"
info "Inner zip created successfully"

# Outer zip

OUTER_ZIP="$OUTPUT_DIR/outer.zip"

info "Creating outer zip (password-protected, wrapping inner zip)..."
debug "Outer zip path    : $OUTER_ZIP"

(cd "$WORK_DIR" && zip -P "$OUTER_PASS" "$OUTER_ZIP" "inner.zip") 2>&1 | while IFS= read -r line; do
    debug "[zip-outer] $line"
done

OUTER_SIZE=$(stat -f'%z' "$OUTER_ZIP" 2>/dev/null || stat --printf='%s' "$OUTER_ZIP" 2>/dev/null)
debug "Outer zip size    : $OUTER_SIZE bytes"
info "Outer zip created successfully"

# Write password files

info "Writing password files..."
echo "$INNER_PASS" > "$OUTPUT_DIR/inner.txt"
debug "Wrote inner password to: $OUTPUT_DIR/inner.txt"
echo "$OUTER_PASS" > "$OUTPUT_DIR/outer.txt"
debug "Wrote outer password to: $OUTPUT_DIR/outer.txt"

# Summary

info "========================================"
info "DONE — Summary"
info "========================================"
info "  Archive  : $OUTER_ZIP"
info "  Inner pw : $OUTPUT_DIR/inner.txt"
info "  Outer pw : $OUTPUT_DIR/outer.txt"
info "  Log      : $LOG_FILE"
info ""
info "To extract:"
info "  1. unzip -P \"\$(cat outer.txt)\" outer.zip"
info "  2. unzip -P \"\$(cat inner.txt)\" inner.zip"
info "========================================"
