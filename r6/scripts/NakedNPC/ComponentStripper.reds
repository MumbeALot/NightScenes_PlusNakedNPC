// NakedNPC - Component Stripper
// ===============================
// Enhanced version of NightScene's PublicAPI.StripEntity().
// Handles two scenarios:
//   1. NPC has a t0_ nude body mesh → toggle off clothing, keep body (standard)
//   2. NPC has NO t0_ body mesh → swap primary clothing mesh to universal nude body (fallback)
//
// Also handles full restoration to pre-strip state.

public abstract class NakedNPCStripper {

    // -------------------------------------------------------
    //  CLOTHING PREFIX CLASSIFICATION
    // -------------------------------------------------------

    /// Returns true if a component name is a clothing prefix that should be stripped.
    private static func IsClothingPrefix(compName: String) -> Bool {
        // Torso clothing layers
        if StrBeginsWith(compName, "t1_") || StrBeginsWith(compName, "t2_") {
            return true;
        }
        // Legs outer clothing (pants, skirts) — NOT l0_ which is legs body/underwear
        if StrBeginsWith(compName, "l1_") {
            return true;
        }
        // Shoes
        if StrBeginsWith(compName, "s1_") {
            return true;
        }
        // Headwear (hats, glasses)
        if StrBeginsWith(compName, "h1_") || StrBeginsWith(compName, "h2_") {
            return true;
        }
        // Accessories (chokers, jewelry)
        if StrBeginsWith(compName, "i1_") {
            return true;
        }
        // Outfit overlay
        if StrBeginsWith(compName, "o1_") {
            return true;
        }
        // Gloves
        if StrBeginsWith(compName, "g1_") {
            return true;
        }
        return false;
    }

    /// Returns true if a component name is a body prefix that should be kept visible.
    private static func IsBodyPrefix(compName: String) -> Bool {
        // Nude body (torso + shoulders + arms)
        if StrBeginsWith(compName, "t0_") {
            return true;
        }
        // Legs body / underwear layer (keep visible, not clothing!)
        if StrBeginsWith(compName, "l0_") {
            return true;
        }
        // Feet body mesh
        if StrBeginsWith(compName, "s0_") {
            return true;
        }
        // Head / face / hair variants
        if StrBeginsWith(compName, "h0_") || StrBeginsWith(compName, "hx_")
            || StrBeginsWith(compName, "ht_") || StrBeginsWith(compName, "he_")
            || StrBeginsWith(compName, "hh_") {
            return true;
        }
        // Arm cyberware / nails
        if StrBeginsWith(compName, "a0_") {
            return true;
        }
        // Inner body layer
        if StrBeginsWith(compName, "i0_") {
            return true;
        }
        return false;
    }

    // -------------------------------------------------------
    //  STRIP
    // -------------------------------------------------------

    /// Strip clothing from an entity. Returns true if stripping succeeded.
    /// This is the main entry point called by AppearanceHook.
    public static func StripNPC(entity: ref<GameObject>) -> Bool {
        let gi = entity.GetGame();
        let system = NakedNPCSystem.GetInstance(gi);

        if !IsDefined(system) || !system.IsEnabled() {
            return false;
        }

        // Don't double-strip
        if system.IsStripped(entity.GetEntityID()) {
            LogChannel(n"NakedNPC", "Entity already stripped, skipping");
            return true;
        }

        // Detect body type
        let bodyType = NakedNPCBodyDetector.Detect(entity);
        LogChannel(n"NakedNPC", "Stripping NPC - bodyType=" + NakedNPCBodyDetector.BodyTypeToString(bodyType));

        // Build saved state
        let savedState = new NakedNPCSavedState();
        savedState.entityID = entity.GetEntityID();
        savedState.originalAppearance = entity.GetCurrentAppearanceName();
        savedState.gender = bodyType;
        savedState.hadNudeBody = false;
        savedState.meshSwapApplied = false;
        savedState.strippedCount = 0;
        savedState.timestamp = EngineTime.ToFloat(GameInstance.GetSimTime(gi));

        // Phase 1: Scan all mesh components, categorize them, check for t0_ body
        let components = entity.GetComponents();
        let hasNudeBody = false;
        let clothingComps: array<ref<IComponent>>;
        let i: Int32 = 0;

        while i < ArraySize(components) {
            let comp = components[i];
            let compName = NameToString(comp.GetName());
            let className = NameToString(comp.GetClassName());

            if StrContains(className, "Mesh") {
                if StrBeginsWith(compName, "t0_") {
                    hasNudeBody = true;
                }
                if NakedNPCStripper.IsClothingPrefix(compName) {
                    ArrayPush(clothingComps, comp);
                }
            }
            i += 1;
        }

        savedState.hadNudeBody = hasNudeBody;

        if system.IsDebugMode() {
            LogChannel(n"NakedNPC", "Found " + IntToString(ArraySize(clothingComps)) + " clothing components, hasNudeBody=" + (hasNudeBody ? "true" : "false"));
        }

        // Phase 2: Toggle off all clothing components AND set chunkMask=0
        i = 0;
        while i < ArraySize(clothingComps) {
            let comp = clothingComps[i];
            let compName = comp.GetName();

            // Save original state
            let compState = new NakedNPCComponentState();
            compState.componentName = compName;
            compState.wasEnabled = comp.IsEnabled();
            compState.isBodyMesh = false;
            compState.meshWasSwapped = false;
            compState.originalMeshPath = "";

            // Save and zero out chunkMask (belt-and-suspenders with Toggle)
            let meshComp = comp as MeshComponent;
            if IsDefined(meshComp) {
                compState.originalChunkMask = meshComp.chunkMask;
                meshComp.chunkMask = 0ul;
            }
            ArrayPush(savedState.components, compState);

            // Hide the clothing component
            comp.Toggle(false);
            savedState.strippedCount += 1;

            if system.IsDebugMode() {
                LogChannel(n"NakedNPC", "  Stripped: " + NameToString(compName));
            }
            i += 1;
        }

        // Phase 3: Reveal ALL chunks on body meshes.
        // The game hides body parts under clothing via chunkMask.
        // We need to set chunkMask = all-bits-on to show the full nude body.
        i = 0;
        while i < ArraySize(components) {
            let comp = components[i];
            let compName = NameToString(comp.GetName());
            let className = NameToString(comp.GetClassName());

            if StrContains(className, "Mesh") && NakedNPCStripper.IsBodyPrefix(compName) {
                let meshComp = comp as MeshComponent;
                if IsDefined(meshComp) {
                    // Save original chunkMask for restore
                    let compState = new NakedNPCComponentState();
                    compState.componentName = comp.GetName();
                    compState.wasEnabled = comp.IsEnabled();
                    compState.originalChunkMask = meshComp.chunkMask;
                    compState.isBodyMesh = true;
                    compState.meshWasSwapped = false;
                    compState.originalMeshPath = "";
                    ArrayPush(savedState.components, compState);

                    // Set ALL chunks visible (18446744073709551615 = 0xFFFFFFFFFFFFFFFF)
                    meshComp.chunkMask = 18446744073709551615ul;

                    // Ensure the body component is enabled
                    if !comp.IsEnabled() {
                        comp.Toggle(true);
                    }

                    if system.IsDebugMode() {
                        LogChannel(n"NakedNPC", "  Body revealed: " + compName + " chunkMask -> ALL");
                    }
                }
            }
            i += 1;
        }

        // Phase 4: If no nude body mesh exists, try mesh swap on primary torso component
        // NOTE: Mesh swap is experimental — MeshComponent.mesh may not be writable at runtime.
        // If it fails, the NPC will have a missing torso (clothing hidden, no body underneath).
        if !hasNudeBody && system.IsMeshSwapEnabled() {
            savedState.meshSwapApplied = NakedNPCStripper.TryMeshSwap(entity, bodyType, savedState);
        }

        // Register with system
        system.RegisterStrip(savedState);

        LogChannel(n"NakedNPC", "Strip complete: " + IntToString(savedState.strippedCount) + " items removed"
            + (savedState.meshSwapApplied ? " (mesh swap applied)" : "")
            + (!hasNudeBody && !savedState.meshSwapApplied ? " WARNING: no nude body found!" : ""));

        return true;
    }

    /// Attempt to swap a clothing mesh with a universal nude body mesh.
    /// NOTE: Mesh swapping via Redscript is not reliably supported (mesh assignment
    /// on MeshComponent is read-only in many game versions). The Lua side handles
    /// mesh swapping via ResRef.FromHash. This function returns false to let Lua handle it.
    private static func TryMeshSwap(entity: ref<GameObject>, bodyType: NakedNPCBodyType, savedState: ref<NakedNPCSavedState>) -> Bool {
        LogChannel(n"NakedNPC", "Mesh swap deferred to CET Lua (Redscript mesh assignment not supported)");
        return false;
    }

    /// Get the depot path for the universal nude body mesh of a given body type.
    /// These are the vanilla game's base body meshes.
    private static func GetNudeBodyMeshPath(bodyType: NakedNPCBodyType) -> String {
        switch bodyType {
            case NakedNPCBodyType.Female:
                return "base\\characters\\common\\base_bodies\\woman_average\\t0_000_wa__c_base_full0.mesh";
            case NakedNPCBodyType.Male:
                return "base\\characters\\common\\base_bodies\\man_average\\t0_001_ma__c_base_full0.mesh";
            case NakedNPCBodyType.MaleBig:
                return "base\\characters\\common\\base_bodies\\man_big\\t0_002_mb__c_base_full0.mesh";
            default:
                return "";
        }
    }

    // -------------------------------------------------------
    //  RESTORE
    // -------------------------------------------------------

    /// Restore a previously stripped NPC to their original appearance.
    /// Returns true if restoration succeeded.
    public static func RestoreNPC(entity: ref<GameObject>) -> Bool {
        let gi = entity.GetGame();
        let system = NakedNPCSystem.GetInstance(gi);

        if !IsDefined(system) {
            return false;
        }

        let savedState = system.GetSavedState(entity.GetEntityID());
        if !IsDefined(savedState) {
            LogChannel(n"NakedNPC", "No saved state for entity, cannot restore");
            return false;
        }

        // Restore all saved component states
        let i: Int32 = 0;
        let restored: Int32 = 0;
        while i < ArraySize(savedState.components) {
            let compState = savedState.components[i];
            let comp = entity.FindComponentByName(compState.componentName);

            if IsDefined(comp) {
                // Restore visibility
                if compState.wasEnabled {
                    comp.Toggle(true);
                } else {
                    comp.Toggle(false);
                }

                // Restore original chunkMask (critical for body meshes!)
                let meshComp = comp as MeshComponent;
                if IsDefined(meshComp) {
                    meshComp.chunkMask = compState.originalChunkMask;
                }

                // If mesh was swapped, the appearance restore below will fix it
                if compState.meshWasSwapped {
                    LogChannel(n"NakedNPC", "Mesh-swapped component will be restored via appearance change");
                }

                restored += 1;
            }
            i += 1;
        }

        // Unregister from system
        system.UnregisterStrip(entity.GetEntityID());

        LogChannel(n"NakedNPC", "Restored " + IntToString(restored) + "/" + IntToString(ArraySize(savedState.components)) + " components");

        return true;
    }

    // -------------------------------------------------------
    //  UTILITY
    // -------------------------------------------------------

    /// Check if an entity has a real nude body mesh (t0_ component).
    /// Useful for other mods to query before deciding their undressing strategy.
    public static func HasNudeBody(entity: ref<GameObject>) -> Bool {
        let components = entity.GetComponents();
        let i: Int32 = 0;
        while i < ArraySize(components) {
            let compName = NameToString(components[i].GetName());
            let className = NameToString(components[i].GetClassName());
            if StrContains(className, "Mesh") && StrBeginsWith(compName, "t0_") {
                return true;
            }
            i += 1;
        }
        return false;
    }

    /// Get a debug dump of all mesh components on an entity.
    /// Returns formatted string for logging/UI display.
    public static func DumpComponents(entity: ref<GameObject>) -> String {
        let result: String = "";
        let components = entity.GetComponents();
        let i: Int32 = 0;
        while i < ArraySize(components) {
            let comp = components[i];
            let compName = NameToString(comp.GetName());
            let className = NameToString(comp.GetClassName());

            if StrContains(className, "Mesh") {
                let prefix = "[?] ";
                if NakedNPCStripper.IsBodyPrefix(compName) {
                    prefix = "[BODY] ";
                } else {
                    if NakedNPCStripper.IsClothingPrefix(compName) {
                        prefix = "[CLOTH] ";
                    }
                }
                let enabled = comp.IsEnabled() ? "ON" : "OFF";
                result += prefix + compName + " (" + enabled + ")\n";
            }
            i += 1;
        }
        return result;
    }
}
