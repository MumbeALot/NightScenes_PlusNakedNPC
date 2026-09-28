// NakedNPC - Core System (Singleton)
// ====================================
// Tracks which NPCs have been stripped by our mod so we can restore them.
// Provides the central registry that AppearanceHook and ComponentStripper use.

/// Saved state for a single mesh component before we stripped it.
public class NakedNPCComponentState extends IScriptable {
    public let componentName: CName;
    public let wasEnabled: Bool;
    public let originalChunkMask: Uint64;
    // If we performed a mesh swap, store the original mesh resource path
    public let originalMeshPath: String;
    public let meshWasSwapped: Bool;
    public let isBodyMesh: Bool;  // true if this was a body mesh whose chunkMask we modified
}

/// Complete saved state for one NPC that we've stripped.
public class NakedNPCSavedState extends IScriptable {
    public let entityID: EntityID;
    public let originalAppearance: CName;
    public let gender: NakedNPCBodyType;
    public let components: array<ref<NakedNPCComponentState>>;
    public let hadNudeBody: Bool;       // true if t0_ body existed
    public let meshSwapApplied: Bool;   // true if we injected a universal nude mesh
    public let strippedCount: Int32;    // how many clothing components we hid
    public let timestamp: Float;        // game time when stripped
}

/// Body type enum for selecting the correct nude mesh.
enum NakedNPCBodyType {
    Unknown   = 0,
    Female    = 1,
    Male      = 2,
    MaleBig   = 3
}

/// Singleton system that persists across the game session.
/// Access via NakedNPCSystem.GetInstance(gameInstance).
public class NakedNPCSystem extends ScriptableSystem {

    private let m_strippedEntities: array<ref<NakedNPCSavedState>>;
    private let m_enabled: Bool;
    private let m_debugMode: Bool;
    private let m_totalStripped: Int32;
    private let m_totalRestored: Int32;
    private let m_meshSwapEnabled: Bool;

    // -------------------------------------------------------
    //  LIFECYCLE
    // -------------------------------------------------------

    private func OnAttach() -> Void {
        this.m_enabled = true;
        this.m_debugMode = false;
        this.m_meshSwapEnabled = true;
        this.m_totalStripped = 0;
        this.m_totalRestored = 0;
        LogChannel(n"NakedNPC", "NakedNPC System initialized");
    }

    private func OnDetach() -> Void {
        LogChannel(n"NakedNPC", "NakedNPC System detaching. Stats: stripped=" + IntToString(this.m_totalStripped) + " restored=" + IntToString(this.m_totalRestored));
    }

    // -------------------------------------------------------
    //  STATIC ACCESSOR
    // -------------------------------------------------------

    /// Get the singleton instance from any game context.
    public static func GetInstance(gi: GameInstance) -> ref<NakedNPCSystem> {
        let system = GameInstance.GetScriptableSystemsContainer(gi).Get(n"NakedNPCSystem") as NakedNPCSystem;
        return system;
    }

    // -------------------------------------------------------
    //  STATE QUERIES
    // -------------------------------------------------------

    /// Check if an entity has been stripped by us.
    public func IsStripped(entityID: EntityID) -> Bool {
        let i: Int32 = 0;
        while i < ArraySize(this.m_strippedEntities) {
            if this.m_strippedEntities[i].entityID == entityID {
                return true;
            }
            i += 1;
        }
        return false;
    }

    /// Get the saved state for a stripped entity (or null if not stripped).
    public func GetSavedState(entityID: EntityID) -> ref<NakedNPCSavedState> {
        let i: Int32 = 0;
        while i < ArraySize(this.m_strippedEntities) {
            if this.m_strippedEntities[i].entityID == entityID {
                return this.m_strippedEntities[i];
            }
            i += 1;
        }
        return null;
    }

    /// Register a newly stripped NPC.
    public func RegisterStrip(state: ref<NakedNPCSavedState>) -> Void {
        // Remove any existing entry for this entity first
        this.UnregisterStrip(state.entityID);
        ArrayPush(this.m_strippedEntities, state);
        this.m_totalStripped += 1;

        if this.m_debugMode {
            LogChannel(n"NakedNPC", "Registered strip for entity " + EntityID.ToDebugString(state.entityID)
                + " gender=" + IntToString(EnumInt(state.gender))
                + " hadBody=" + (state.hadNudeBody ? "true" : "false")
                + " meshSwap=" + (state.meshSwapApplied ? "true" : "false")
                + " clothingRemoved=" + IntToString(state.strippedCount));
        }
    }

    /// Unregister a stripped NPC (after restoring).
    public func UnregisterStrip(entityID: EntityID) -> Void {
        let i: Int32 = 0;
        while i < ArraySize(this.m_strippedEntities) {
            if this.m_strippedEntities[i].entityID == entityID {
                ArrayErase(this.m_strippedEntities, i);
                this.m_totalRestored += 1;
                return;
            }
            i += 1;
        }
    }

    // -------------------------------------------------------
    //  CONFIG
    // -------------------------------------------------------

    public func IsEnabled() -> Bool {
        return this.m_enabled;
    }

    public func SetEnabled(enabled: Bool) -> Void {
        this.m_enabled = enabled;
        LogChannel(n"NakedNPC", "Mod " + (enabled ? "enabled" : "disabled"));
    }

    public func IsDebugMode() -> Bool {
        return this.m_debugMode;
    }

    public func SetDebugMode(debug: Bool) -> Void {
        this.m_debugMode = debug;
    }

    public func IsMeshSwapEnabled() -> Bool {
        return this.m_meshSwapEnabled;
    }

    public func SetMeshSwapEnabled(enabled: Bool) -> Void {
        this.m_meshSwapEnabled = enabled;
    }

    // -------------------------------------------------------
    //  STATS
    // -------------------------------------------------------

    public func GetCurrentStrippedCount() -> Int32 {
        return ArraySize(this.m_strippedEntities);
    }

    public func GetTotalStripped() -> Int32 {
        return this.m_totalStripped;
    }

    public func GetTotalRestored() -> Int32 {
        return this.m_totalRestored;
    }

    /// Get all currently stripped entity states (for UI display).
    public func GetAllStrippedStates() -> array<ref<NakedNPCSavedState>> {
        return this.m_strippedEntities;
    }

    // -------------------------------------------------------
    //  CLEANUP
    // -------------------------------------------------------

    /// Remove entries for entities that no longer exist in the world.
    /// Called periodically from CET Lua onUpdate.
    public func CleanupDespawned() -> Int32 {
        let gi = this.GetGameInstance();
        let removed: Int32 = 0;
        let i: Int32 = ArraySize(this.m_strippedEntities) - 1;
        while i >= 0 {
            let entity = GameInstance.FindEntityByID(gi, this.m_strippedEntities[i].entityID);
            if !IsDefined(entity) {
                if this.m_debugMode {
                    LogChannel(n"NakedNPC", "Cleaning up despawned entity: " + EntityID.ToDebugString(this.m_strippedEntities[i].entityID));
                }
                ArrayErase(this.m_strippedEntities, i);
                removed += 1;
            }
            i -= 1;
        }
        return removed;
    }

    // -------------------------------------------------------
    //  HOOK BRIDGE (called from CET Lua ObserveBefore)
    // -------------------------------------------------------

    /// Called from CET Lua when a _naked appearance is requested
    /// and no real _naked appearance exists.
    public func HandleNakedRequest(entity: ref<GameObject>) -> Bool {
        if !this.m_enabled {
            return false;
        }
        return NakedNPCStripper.StripNPC(entity);
    }

    /// Called from CET Lua when a non-_naked appearance is requested
    /// on an entity we previously stripped.
    public func HandleRestore(entity: ref<GameObject>) -> Bool {
        return NakedNPCStripper.RestoreNPC(entity);
    }

    /// Check if entity has a real t0_ body mesh.
    public func CheckHasNudeBody(entity: ref<GameObject>) -> Bool {
        return NakedNPCStripper.HasNudeBody(entity);
    }

    /// Debug: get formatted component list for an entity.
    public func GetComponentDump(entity: ref<GameObject>) -> String {
        return NakedNPCStripper.DumpComponents(entity);
    }

    /// Detect body type and return as int (1=Female, 2=Male, 3=MaleBig).
    public func DetectBodyType(entity: ref<GameObject>) -> Int32 {
        return EnumInt(NakedNPCBodyDetector.Detect(entity));
    }

    /// Check if entity has a real _naked appearance (joytoys, romance NPCs).
    /// Called from CET Lua to decide whether to let native handle it.
    public func CheckHasRealNakedAppearance(entity: ref<GameObject>) -> Bool {
        let puppet = entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return false;
        }
        return NakedNPCHookHelper.HasRealAppearance(puppet);
    }

    // -------------------------------------------------------
    //  NIGHTSCENE INTEGRATION
    // -------------------------------------------------------

    /// Strip an NPC for a NightScene animation (immediate, no appearance cycle).
    /// Uses component toggling + chunkMask. Called from NightScene's Redscript.
    /// @param genitalState - "soft", "erect", or "" for default
    public func StripForScene(entity: ref<GameObject>, genitalState: String) -> Bool {
        if !this.m_enabled {
            return false;
        }
        // Delegate to the component stripper (immediate path)
        return NakedNPCStripper.StripNPC(entity);
    }

    /// Restore an NPC after a NightScene scene ends.
    public func RestoreFromScene(entity: ref<GameObject>) -> Bool {
        return NakedNPCStripper.RestoreNPC(entity);
    }

    /// Remove items from ALL equipment slots on an entity.
    /// Used for Clone V — clears inventory so clothing can't re-appear.
    /// Works with any mod's clothing since it operates at inventory level, not component level.
    public func StripAllSlots(entity: ref<GameObject>) -> Void {
        let gi = entity.GetGame();
        let ts = GameInstance.GetTransactionSystem(gi);

        let slots: array<TweakDBID>;
        ArrayPush(slots, t"AttachmentSlots.Head");
        ArrayPush(slots, t"AttachmentSlots.Chest");
        ArrayPush(slots, t"AttachmentSlots.Torso");
        ArrayPush(slots, t"AttachmentSlots.Outfit");
        ArrayPush(slots, t"AttachmentSlots.Legs");
        ArrayPush(slots, t"AttachmentSlots.Feet");
        ArrayPush(slots, t"AttachmentSlots.Hands");
        ArrayPush(slots, t"AttachmentSlots.Eyes");
        ArrayPush(slots, t"AttachmentSlots.UnderwearTop");
        ArrayPush(slots, t"AttachmentSlots.UnderwearBottom");

        let i: Int32 = 0;
        while i < ArraySize(slots) {
            ts.RemoveItemFromSlot(entity, slots[i]);
            i += 1;
        }

        LogChannel(n"NakedNPC", "Cleared all 10 equipment slots on entity");
    }

    // -------------------------------------------------------
    //  CLONE V: Unequip/Re-equip player clothing
    // -------------------------------------------------------

    private let m_savedItemIDs: array<ItemID>;
    private let m_playerWasUnequipped: Bool;

    /// Unequip ALL clothing from the player using the REAL EquipmentSystem unequip.
    /// This is the same as the player manually removing gear from the inventory screen.
    /// Clone V inherits the player's equipment state, so unequipping before spawn = naked clone.
    public func UnequipPlayerClothing() -> Void {
        let player = GetPlayer(this.GetGameInstance()) as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }

        let equipData = EquipmentSystem.GetData(player);

        // Clothing equipment areas to unequip
        let areas: array<gamedataEquipmentArea>;
        ArrayPush(areas, gamedataEquipmentArea.Head);
        ArrayPush(areas, gamedataEquipmentArea.Face);
        ArrayPush(areas, gamedataEquipmentArea.InnerChest);
        ArrayPush(areas, gamedataEquipmentArea.OuterChest);
        ArrayPush(areas, gamedataEquipmentArea.Legs);
        ArrayPush(areas, gamedataEquipmentArea.Feet);
        ArrayPush(areas, gamedataEquipmentArea.Outfit);
        ArrayPush(areas, gamedataEquipmentArea.UnderwearTop);
        ArrayPush(areas, gamedataEquipmentArea.UnderwearBottom);

        ArrayClear(this.m_savedItemIDs);
        let unequippedCount: Int32 = 0;

        let i: Int32 = 0;
        while i < ArraySize(areas) {
            let areaIndex = equipData.GetEquipAreaIndex(areas[i]);
            // Save the equipped item ID BEFORE unequipping (unequip clears the slot)
            let itemID = equipData.GetItemInEquipSlot(areaIndex, 0);
            if ItemID.IsValid(itemID) {
                ArrayPush(this.m_savedItemIDs, itemID);
            }
            // Call the real unequip — both data AND visuals
            equipData.NakedNPC_UnequipArea(areaIndex, areas[i]);
            unequippedCount += 1;
            i += 1;
        }

        this.m_playerWasUnequipped = true;
        LogChannel(n"NakedNPC", "Unequipped " + IntToString(unequippedCount) + " equipment areas from player");
    }

    /// Re-equip player clothing after scene ends using saved item IDs.
    public func ReequipPlayerClothing() -> Void {
        if !this.m_playerWasUnequipped {
            return;
        }

        let player = GetPlayer(this.GetGameInstance()) as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }

        let equipData = EquipmentSystem.GetData(player);

        // Re-equip each saved item
        let i: Int32 = 0;
        while i < ArraySize(this.m_savedItemIDs) {
            if ItemID.IsValid(this.m_savedItemIDs[i]) {
                equipData.EquipItem(this.m_savedItemIDs[i]);
            }
            i += 1;
        }

        this.m_playerWasUnequipped = false;
        LogChannel(n"NakedNPC", "Re-equipped " + IntToString(ArraySize(this.m_savedItemIDs)) + " saved items on player");
        ArrayClear(this.m_savedItemIDs);
    }
}
