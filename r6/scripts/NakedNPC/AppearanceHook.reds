// NakedNPC - Appearance Hook Helpers
// =====================================
// Utility functions for the CET Lua-side ObserveBefore hook.
// The actual hook lives in init.lua because ScheduleAppearanceChange
// is a NATIVE method on entEntity — it cannot be wrapped with @wrapMethod.
//
// The hook bridge methods (HandleNakedRequest, HandleRestore, etc.) are
// defined directly on NakedNPCSystem in NakedNPCSystem.reds.
//
// This file contains only the static helper class for appearance checks.

/// Static helper functions used by CET Lua to check appearance names.
public abstract class NakedNPCHookHelper {

    /// Check if a string ends with "_naked" or "_naked_ltd".
    public static func EndsWithNaked(name: String) -> Bool {
        return StrEndsWith(name, "_naked") || StrEndsWith(name, "_naked_ltd");
    }

    /// Check if an entity has a REAL _naked appearance in its template.
    /// Uses heuristics based on character record IDs since we can't
    /// enumerate .ent appearances from Redscript.
    public static func HasRealAppearance(entity: ref<ScriptedPuppet>) -> Bool {
        let recordID = entity.GetRecordID();
        let record = TweakDBInterface.GetCharacterRecord(recordID);

        if !IsDefined(record) {
            return false;
        }

        let recordStr = TDBID.ToStringDEBUG(recordID);

        // Known character types that have _naked appearances
        if StrContains(recordStr, "Joytoy") || StrContains(recordStr, "joytoy") {
            return true;
        }
        if StrContains(recordStr, "Panam") || StrContains(recordStr, "Judy")
            || StrContains(recordStr, "River") || StrContains(recordStr, "Kerry")
            || StrContains(recordStr, "Alt_Cunningham") || StrContains(recordStr, "alt_cunningham")
            || StrContains(recordStr, "Meredith") {
            return true;
        }

        // Common NPC archetypes that NEVER have _naked
        if StrContains(recordStr, "citizen") || StrContains(recordStr, "gang")
            || StrContains(recordStr, "corpo") || StrContains(recordStr, "vendor")
            || StrContains(recordStr, "fixer") || StrContains(recordStr, "police")
            || StrContains(recordStr, "Guard") || StrContains(recordStr, "Civilian")
            || StrContains(recordStr, "Crowd") {
            return false;
        }

        // Default: assume no real _naked variant for unknown NPCs
        return false;
    }
}
