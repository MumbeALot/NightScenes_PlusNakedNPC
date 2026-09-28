// NakedNPC - Body Type Detector
// ===============================
// Detects NPC gender/body type for selecting the correct universal nude mesh.
// Uses the same detection chain as NightScene's ActorController.DetectGender
// with additional fallbacks.

public abstract class NakedNPCBodyDetector {

    /// Detect body type of any game entity.
    /// Priority: Player gender → AnimatedComponent rig path → FX components → VisualTags → fallback.
    public static func Detect(entity: ref<GameObject>) -> NakedNPCBodyType {
        // 1. Player character — use resolved gender
        if entity.IsPlayer() {
            let player = entity as PlayerPuppet;
            if IsDefined(player) {
                let genderName = player.GetResolvedGenderName();
                if Equals(genderName, n"Female") {
                    return NakedNPCBodyType.Female;
                }
                return NakedNPCBodyType.Male;
            }
        }

        // 2. AnimatedComponent rig path — most reliable for NPCs
        let animComp = entity.FindComponentByName(n"root") as AnimatedComponent;
        if IsDefined(animComp) {
            let rigPath = ResRef.ToString(ResourceRef.GetPath(animComp.rig));
            if NotEquals(rigPath, "") {
                if StrContains(rigPath, "woman") {
                    return NakedNPCBodyType.Female;
                }
                if StrContains(rigPath, "man_big") || StrContains(rigPath, "man_massive") || StrContains(rigPath, "man_fat") {
                    return NakedNPCBodyType.MaleBig;
                }
                if StrContains(rigPath, "man") {
                    return NakedNPCBodyType.Male;
                }
            }
        }

        // 3. FX component presence — widely supported fallback
        let femComp = entity.FindComponentByName(n"fx_woman_base");
        if IsDefined(femComp) {
            return NakedNPCBodyType.Female;
        }

        let maleComp = entity.FindComponentByName(n"fx_man_base");
        if IsDefined(maleComp) {
            return NakedNPCBodyType.Male;
        }

        // 4. Character record VisualTags — last resort for NPCs with TweakDB records
        let puppet = entity as ScriptedPuppet;
        if IsDefined(puppet) {
            let record = TweakDBInterface.GetCharacterRecord(puppet.GetRecordID());
            if IsDefined(record) {
                let tags = record.VisualTags();
                let i: Int32 = 0;
                while i < ArraySize(tags) {
                    let tag = tags[i];
                    if Equals(tag, n"Female") || Equals(tag, n"Woman") {
                        return NakedNPCBodyType.Female;
                    }
                    if Equals(tag, n"Male") || Equals(tag, n"Man") {
                        return NakedNPCBodyType.Male;
                    }
                    i += 1;
                }
            }
        }

        // 5. Heuristic: check mesh component names for gender hints
        //    e.g. "t0_000_wa_" → female (wa = woman average)
        //         "t0_001_ma_" → male average
        //         "t0_002_mb_" → male big
        let bodyType = NakedNPCBodyDetector.DetectFromMeshNames(entity);
        if NotEquals(bodyType, NakedNPCBodyType.Unknown) {
            return bodyType;
        }

        LogChannel(n"NakedNPC", "WARN: Could not detect body type, defaulting to Female");
        return NakedNPCBodyType.Female;
    }

    /// Try to infer body type from mesh component naming conventions.
    /// CP2077 uses: wa = woman average, ma = man average, mb = man big
    private static func DetectFromMeshNames(entity: ref<GameObject>) -> NakedNPCBodyType {
        let components = entity.GetComponents();
        let i: Int32 = 0;
        while i < ArraySize(components) {
            let compName = NameToString(components[i].GetName());

            // Look for body or clothing components with gender codes
            if StrBeginsWith(compName, "t0_") || StrBeginsWith(compName, "t1_") || StrBeginsWith(compName, "l0_") {
                if StrContains(compName, "_wa_") || StrContains(compName, "_wa__") || StrContains(compName, "_pwa_") {
                    return NakedNPCBodyType.Female;
                }
                if StrContains(compName, "_mb_") || StrContains(compName, "_mb__") || StrContains(compName, "_pmb_") {
                    return NakedNPCBodyType.MaleBig;
                }
                if StrContains(compName, "_ma_") || StrContains(compName, "_ma__") || StrContains(compName, "_pma_") {
                    return NakedNPCBodyType.Male;
                }
            }
            i += 1;
        }
        return NakedNPCBodyType.Unknown;
    }

    /// Convert body type enum to a human-readable string (for logging/UI).
    public static func BodyTypeToString(bodyType: NakedNPCBodyType) -> String {
        switch bodyType {
            case NakedNPCBodyType.Female:
                return "Female";
            case NakedNPCBodyType.Male:
                return "Male";
            case NakedNPCBodyType.MaleBig:
                return "MaleBig";
            default:
                return "Unknown";
        }
    }
}
