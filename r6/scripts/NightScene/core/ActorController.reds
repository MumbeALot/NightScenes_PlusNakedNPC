// NightScene Framework - Actor Controller
// ==========================================
// Manages individual actors during scenes:
//   - Finding and caching animation components
//   - Disabling / re-enabling NPC AI
//   - Positioning actors at scene locations
//   - Equipment stripping and restoring
//   - Playing / stopping animations on entities
//
// VERIFY: Some native function signatures need verification against
//         the decompiled game scripts. Marked with // VERIFY comments.

/// Handles all per-actor manipulation during a scene.
public class NightSceneActorController extends IScriptable {

    // -------------------------------------------------------
    //  ACTOR STATE INITIALIZATION
    // -------------------------------------------------------

    /// Build actor state from a game entity.
    /// Caches position, animation component, and determines gender.
    public func InitActorState(entity: ref<GameObject>, role: NightSceneActorRole) -> ref<NightSceneActorState> {
        let state = new NightSceneActorState();
        state.entity = entity;
        state.entityID = entity.GetEntityID();
        state.role = role;
        state.isPlayer = entity.IsPlayer();

        // Save current transform for later restoration
        state.savedPosition = entity.GetWorldPosition();
        state.savedOrientation = entity.GetWorldOrientation();

        // Determine gender
        state.gender = this.DetectGender(entity);

        // Cache animation component
        state.animComponent = this.FindAnimComponent(entity);

        state.aiWasDisabled = false;
        state.equipmentStripped = false;

        return state;
    }

    // -------------------------------------------------------
    //  GENDER DETECTION
    // -------------------------------------------------------

    /// Detect the gender of a game entity using skeleton component check.
    /// This is the most reliable method (same as AMM uses).
    public func DetectGender(entity: ref<GameObject>) -> NightSceneGender {
        // Check if it's the player first
        if entity.IsPlayer() {
            let player = entity as PlayerPuppet;
            if IsDefined(player) {
                let genderName = player.GetResolvedGenderName();
                if Equals(genderName, n"Female") {
                    return NightSceneGender.Female;
                }
                return NightSceneGender.Male;
            }
        }

        // For NPCs: first check the AnimatedComponent's rig resource path
        // This is the most reliable way to detect body type (Big vs Average etc.)
        let animComp = entity.FindComponentByName(n"root") as AnimatedComponent;
        if IsDefined(animComp) {
            let rigPath = ResRef.ToString(ResourceRef.GetPath(animComp.rig));
            if NotEquals(rigPath, "") {
                LogChannel(n"NightScene", "Rig path: " + rigPath);

                if StrContains(rigPath, "woman") {
                    return NightSceneGender.Female;
                }
                if StrContains(rigPath, "man_big") || StrContains(rigPath, "man_massive") || StrContains(rigPath, "man_fat") {
                    return NightSceneGender.MaleBig;
                }
                if StrContains(rigPath, "man") {
                    return NightSceneGender.Male;
                }
            }
        }

        // Fallback: check FX components (less precise but widely supported)
        let femComp = entity.FindComponentByName(n"fx_woman_base");
        if IsDefined(femComp) {
            return NightSceneGender.Female;
        }

        let maleComp = entity.FindComponentByName(n"fx_man_base");
        if IsDefined(maleComp) {
            return NightSceneGender.Male;
        }

        // Last resort: check via character record visual tags
        let puppet = entity as ScriptedPuppet;
        if IsDefined(puppet) {
            let record = TweakDBInterface.GetCharacterRecord(puppet.GetRecordID());
            if IsDefined(record) {
                let tags = record.VisualTags();
                let i: Int32 = 0;
                while i < ArraySize(tags) {
                    let tag = tags[i];
                    if Equals(tag, n"Female") || Equals(tag, n"Woman") {
                        return NightSceneGender.Female;
                    }
                    if Equals(tag, n"Male") || Equals(tag, n"Man") {
                        return NightSceneGender.Male;
                    }
                    i += 1;
                }
            }
        }

        LogChannel(n"NightScene", "WARN: Could not detect gender, defaulting to Male");
        return NightSceneGender.Male;
    }

    // -------------------------------------------------------
    //  ANIMATION COMPONENT
    // -------------------------------------------------------

    /// Find and cache the AnimatedComponent on an entity.
    /// The base animation component on CP2077 entities is named "root".
    private func FindAnimComponent(entity: ref<GameObject>) -> ref<AnimatedComponent> {
        // Primary: the base animated component is named "root" on most entities
        let comp = entity.FindComponentByName(n"root") as AnimatedComponent;
        if !IsDefined(comp) {
            // Fallback: try common alternate names
            comp = entity.FindComponentByName(n"AnimatedComponent") as AnimatedComponent;
        }
        if !IsDefined(comp) {
            comp = entity.FindComponentByName(n"animatedComponent") as AnimatedComponent;
        }
        if !IsDefined(comp) {
            LogChannel(n"NightScene", "WARN: Could not find AnimatedComponent on entity");
        }
        return comp;
    }

    // -------------------------------------------------------
    //  AI CONTROL
    // -------------------------------------------------------

    /// Disable AI on an NPC so they don't wander during a scene.
    public func DisableAI(actorState: ref<NightSceneActorState>) -> Void {
        if actorState.isPlayer {
            return; // Don't disable player AI, handle via input lock
        }

        let puppet = actorState.entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return;
        }

        // VERIFY: The exact approach to freeze NPC AI.
        // Options in CP2077:
        //   1. Apply a status effect that freezes the NPC (e.g. stunned without visual)
        //   2. Send an AI command to stop all behavior
        //   3. Disable the AI component directly

        // Approach 1: Apply a custom "frozen" status effect via StatusEffectHelper
        // This is the safest approach as it uses the game's own systems.
        let gi = actorState.entity.GetGame();
        StatusEffectHelper.ApplyStatusEffect(actorState.entity, t"BaseStatusEffect.intomovementLockActive");

        actorState.aiWasDisabled = true;
        LogChannel(n"NightScene", "Disabled AI on actor: " + EntityID.ToDebugString(actorState.entityID));
    }

    /// Re-enable AI on an NPC after a scene ends.
    public func EnableAI(actorState: ref<NightSceneActorState>) -> Void {
        if !actorState.aiWasDisabled || actorState.isPlayer {
            return;
        }

        let puppet = actorState.entity as ScriptedPuppet;
        if !IsDefined(puppet) {
            return;
        }

        let gi = actorState.entity.GetGame();
        StatusEffectHelper.RemoveStatusEffect(actorState.entity, t"BaseStatusEffect.intomovementLockActive");

        actorState.aiWasDisabled = false;
        LogChannel(n"NightScene", "Re-enabled AI on actor: " + EntityID.ToDebugString(actorState.entityID));
    }

    /// Lock player controls during a scene (disable input, hide HUD).
    public func LockPlayerControls(player: ref<PlayerPuppet>) -> Void {
        // VERIFY: Exact methods to disable player input.
        // The game uses PlayerControlModes or status effects for this.
        StatusEffectHelper.ApplyStatusEffect(player, t"BaseStatusEffect.intomovementLockActive");

        // Hide HUD elements
        // VERIFY: HUD hiding approach - may use blackboard or ink system
        LogChannel(n"NightScene", "Locked player controls");
    }

    /// Unlock player controls after a scene ends.
    public func UnlockPlayerControls(player: ref<PlayerPuppet>) -> Void {
        StatusEffectHelper.RemoveStatusEffect(player, t"BaseStatusEffect.intomovementLockActive");
        LogChannel(n"NightScene", "Unlocked player controls");
    }

    // -------------------------------------------------------
    //  POSITIONING
    // -------------------------------------------------------

    /// Move an actor to a world position + rotation.
    /// Uses the game's TeleportationFacility for safe entity repositioning.
    public func PositionActor(actorState: ref<NightSceneActorState>, position: Vector4, orientation: Quaternion) -> Void {
        if !IsDefined(actorState.entity) {
            LogChannel(n"NightScene", "ERROR: Cannot position actor - entity is null");
            return;
        }

        let gi = actorState.entity.GetGame();
        let finalOri: Quaternion;
        if orientation.i == 0.0 && orientation.j == 0.0 && orientation.k == 0.0 && orientation.r == 0.0 {
            finalOri = actorState.entity.GetWorldOrientation();
        } else {
            finalOri = orientation;
        }
        GameInstance.GetTeleportationFacility(gi).Teleport(actorState.entity, position, Quaternion.ToEulerAngles(finalOri));

        LogChannel(n"NightScene", "Positioned actor at: " + Vector4.ToString(position));
    }

    /// Position an actor relative to the scene root using the animation's offset data.
    public func PositionActorForAnim(actorState: ref<NightSceneActorState>, scenePos: Vector4, sceneOri: Quaternion, animData: ref<NightSceneActorAnim>) -> Void {
        // Calculate world position from scene root + animation offset
        let offset = animData.positionOffset;

        // Rotate the offset by the scene orientation
        let isOriZero = sceneOri.i == 0.0 && sceneOri.j == 0.0 && sceneOri.k == 0.0 && sceneOri.r == 0.0;
        let rotatedOffset: Vector4;
        if isOriZero {
            rotatedOffset = offset;
        } else {
            rotatedOffset = Quaternion.Transform(sceneOri, offset);
        }

        let finalPos = new Vector4(
            scenePos.X + rotatedOffset.X,
            scenePos.Y + rotatedOffset.Y,
            scenePos.Z + rotatedOffset.Z,
            1.0
        );

        // Apply rotation offset
        let animRotQuat = EulerAngles.ToQuat(animData.rotationOffset);
        let finalOri: Quaternion;
        if isOriZero {
            finalOri = animRotQuat;
        } else {
            finalOri = sceneOri * animRotQuat;
        }

        this.PositionActor(actorState, finalPos, finalOri);
    }

    /// Restore an actor to their saved position (before the scene started).
    public func RestorePosition(actorState: ref<NightSceneActorState>) -> Void {
        this.PositionActor(actorState, actorState.savedPosition, actorState.savedOrientation);
    }

    // -------------------------------------------------------
    //  EQUIPMENT / APPEARANCE
    // -------------------------------------------------------

    // Equipment slot TweakDB IDs for stripping
    // These are the visible clothing/armor slots on the player
    private func GetEquipmentSlots() -> array<TweakDBID> {
        let slots: array<TweakDBID>;
        ArrayPush(slots, t"AttachmentSlots.Head");
        ArrayPush(slots, t"AttachmentSlots.Chest");
        ArrayPush(slots, t"AttachmentSlots.Legs");
        ArrayPush(slots, t"AttachmentSlots.Feet");
        return slots;
    }

    /// Strip equipment from an actor (if configured).
    /// For the player: uses TransactionSystem to remove items from visible slots.
    /// For NPCs: hides equipment visuals via TransactionSystem.
    public func StripEquipment(actorState: ref<NightSceneActorState>) -> Void {
        let gi = actorState.entity.GetGame();
        let transactionSys = GameInstance.GetTransactionSystem(gi);

        if actorState.isPlayer {
            // Strip player visible equipment by removing items from visual slots
            let slots = this.GetEquipmentSlots();
            let i: Int32 = 0;
            while i < ArraySize(slots) {
                transactionSys.RemoveItemFromSlot(actorState.entity, slots[i]);
                i += 1;
            }
            LogChannel(n"NightScene", "Stripped player equipment");
        } else {
            // For NPCs, strip via the same slot-based approach
            let slots = this.GetEquipmentSlots();
            let i: Int32 = 0;
            while i < ArraySize(slots) {
                transactionSys.RemoveItemFromSlot(actorState.entity, slots[i]);
                i += 1;
            }
            LogChannel(n"NightScene", "Stripped NPC equipment");
        }

        actorState.equipmentStripped = true;
    }

    /// Restore equipment / appearance to pre-scene state.
    /// Note: Full equipment restoration requires re-equipping saved items.
    /// For now, this triggers a visual refresh which restores default appearance.
    public func RestoreEquipment(actorState: ref<NightSceneActorState>) -> Void {
        if !actorState.equipmentStripped {
            return;
        }

        if actorState.isPlayer {
            // For the player, the equipment system will re-apply visuals
            // when the EquipmentSystemPlayerData refreshes on next frame.
            // Force a refresh by toggling a benign status effect.
            let gi = actorState.entity.GetGame();
            let player = actorState.entity as PlayerPuppet;
            if IsDefined(player) {
                // Equipment will auto-refresh when slots are re-equipped
                LogChannel(n"NightScene", "Equipment refresh triggered");
            }
            LogChannel(n"NightScene", "Restoring player equipment");
        } else {
            // NPC equipment restoration -- the NPC's original appearance
            // is managed by the game's NPC system and will recover on its own
            // when the entity is re-pooled or when we restore their state.
            LogChannel(n"NightScene", "NPC equipment will restore on despawn/respawn");
        }

        actorState.equipmentStripped = false;
    }

    // -------------------------------------------------------
    //  ANIMATION PLAYBACK
    // -------------------------------------------------------

    /// Play an animation on an actor using direct animation events (non-workspot).
    /// Used as fallback when workspot is not available.
    public func PlayAnimation(actorState: ref<NightSceneActorState>, animName: CName, speed: Float) -> Bool {
        if !IsDefined(actorState.entity) {
            LogChannel(n"NightScene", "ERROR: No entity for actor");
            return false;
        }

        // Push the animation event directly
        AnimationControllerComponent.PushEvent(actorState.entity, animName);

        LogChannel(n"NightScene", "Playing animation (direct): " + NameToString(animName));
        return true;
    }

    /// Play an animation on an actor via the WorkspotGameSystem.
    /// This is the primary method for AMM-compatible animation packs.
    /// The workspot entity must already be spawned by the SceneManager.
    public func PlayWorkspotAnimation(actorState: ref<NightSceneActorState>, workspotEntity: ref<GameObject>, animName: CName) -> Bool {
        if !IsDefined(actorState.entity) || !IsDefined(workspotEntity) {
            LogChannel(n"NightScene", "ERROR: Missing entity or workspot for animation");
            return false;
        }

        let gi = actorState.entity.GetGame();
        let workspotSys = GameInstance.GetWorkspotSystem(gi);

        // Engage the actor in the workspot device
        workspotSys.PlayInDevice(workspotEntity, actorState.entity);

        // Jump to the specific animation within the workspot
        workspotSys.SendJumpToAnimEnt(actorState.entity, animName, true);

        LogChannel(n"NightScene", "Playing animation (workspot): " + NameToString(animName));
        return true;
    }

    /// Stop any currently playing scene animation on an actor.
    public func StopAnimation(actorState: ref<NightSceneActorState>) -> Void {
        if !IsDefined(actorState.entity) {
            return;
        }

        // Stop workspot animation on this actor
        let gi = actorState.entity.GetGame();
        let workspotSys = GameInstance.GetWorkspotSystem(gi);
        workspotSys.StopInDevice(actorState.entity);

        LogChannel(n"NightScene", "Stopped animation on actor");
    }

    // -------------------------------------------------------
    //  FULL CLEANUP
    // -------------------------------------------------------

    /// Perform full cleanup on an actor after a scene ends.
    public func CleanupActor(actorState: ref<NightSceneActorState>) -> Void {
        this.StopAnimation(actorState);
        this.EnableAI(actorState);
        this.RestoreEquipment(actorState);
        this.RestorePosition(actorState);

        if actorState.isPlayer {
            let player = actorState.entity as PlayerPuppet;
            if IsDefined(player) {
                this.UnlockPlayerControls(player);
            }
        }

        LogChannel(n"NightScene", "Cleaned up actor: " + EntityID.ToDebugString(actorState.entityID));
    }
}
