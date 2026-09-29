// NightScene Framework - Public API
// ====================================
// This is the public-facing API that other mods use to interact with
// the NightScene framework. It provides static functions that can be
// called from both Redscript and CET Lua.
//
// USAGE FROM ANOTHER REDSCRIPT MOD:
//   NightSceneAPI.TriggerInteractionHotkey();
//
// USAGE FROM CET LUA:
//   Game.GetNightSceneAPI():TriggerInteractionHotkey()
//   -- or via static calls depending on CET RTTI access

/// The public API class. All methods are static for easy access.
public abstract class NightSceneAPI {

    // ============================================================
    //  SCENE CONTROL
    // ============================================================

    /// Start a scene with a specific animation ID and actor entities.
    public static func StartScene(animId: String, actors: array<ref<GameObject>>) -> Bool {
        let registry = NightSceneServices.Get().AnimRegistry();
        let animDef = registry.GetAnimationById(animId);

        if !IsDefined(animDef) {
            LogChannel(n"NightScene", "API: Animation not found: " + animId);
            return false;
        }

        let zeroPos = new Vector4(0.0, 0.0, 0.0, 0.0);
        return NightSceneServices.Get().SceneManager().StartScene(animDef, actors, NightSceneTriggerSource.API, zeroPos);
    }

    /// Start a scene with a random animation matching the given tags.
    public static func StartRandomScene(
        tags: array<String>,
        actors: array<ref<GameObject>>
    ) -> Bool {
        let registry = NightSceneServices.Get().AnimRegistry();
        let actorCount = ArraySize(actors);

        // Determine genders from actors
        let genders: array<NightSceneGender>;
        let actorCtrl = NightSceneServices.Get().ActorController();
        let i: Int32 = 0;
        while i < actorCount {
            let gender = actorCtrl.DetectGender(actors[i]);
            ArrayPush(genders, gender);
            i += 1;
        }

        let animDef = registry.GetRandom(tags, actorCount, genders, false);
        if !IsDefined(animDef) {
            LogChannel(n"NightScene", "API: No matching animation found for tags");
            return false;
        }

        let zeroPos = new Vector4(0.0, 0.0, 0.0, 0.0);
        return NightSceneServices.Get().SceneManager().StartScene(animDef, actors, NightSceneTriggerSource.API, zeroPos);
    }

    /// Quick start: find the NPC the player is looking at (or nearest in front)
    /// and start an interaction scene, or route to the defeat scene if that NPC
    /// is defeated. This is what the CET "Interact with NPC" hotkey calls -- it's
    /// a thin wrapper around NightSceneInteractionHandler.OnInteractionHotkey,
    /// which does all the actual eligibility/defeat-routing/animation-selection work.
    public static func TriggerInteractionHotkey() -> Void {
        NightSceneServices.Get().InteractionHandler().OnInteractionHotkey();
    }

    /// Stop the currently active scene.
    public static func StopScene() -> Void {
        NightSceneServices.Get().SceneManager().CancelScene();
    }

    /// Advance to the next animation stage.
    public static func NextStage() -> Void {
        NightSceneServices.Get().SceneManager().NextStage();
    }

    /// Go back to the previous animation stage.
    public static func PreviousStage() -> Void {
        NightSceneServices.Get().SceneManager().PreviousStage();
    }

    /// Switch to another animation without stopping the scene. direction is
    /// +1 / -1. Returns false when nothing compatible is available.
    public static func CycleAnimation(direction: Int32) -> Bool {
        return NightSceneServices.Get().SceneManager().CycleAnimation(direction);
    }

    /// Read-and-clear flag: true when the animation or stage changed and the
    /// Lua side needs to re-point the existing actors at the new clips.
    public static func ConsumePendingWorkspotUpdate() -> Bool {
        return NightSceneServices.Get().SceneManager().ConsumePendingWorkspotUpdate();
    }

    /// Display name of the running animation ("" when no scene is active).
    public static func GetActiveSceneAnimationLabel() -> String {
        let scene = NightSceneServices.Get().SceneManager().GetActiveScene();
        if IsDefined(scene) && IsDefined(scene.animDef) {
            return scene.animDef.displayName;
        }
        return "";
    }

    /// 1-based stage number of the running scene (0 when none is active).
    public static func GetActiveSceneStageNumber() -> Int32 {
        let scene = NightSceneServices.Get().SceneManager().GetActiveScene();
        if IsDefined(scene) {
            return scene.currentStageIndex + 1;
        }
        return 0;
    }

    /// Total stages in the running scene (0 when none is active).
    public static func GetActiveSceneStageCount() -> Int32 {
        let scene = NightSceneServices.Get().SceneManager().GetActiveScene();
        if IsDefined(scene) {
            return scene.GetStageCount();
        }
        return 0;
    }

    /// Set animation playback speed.
    public static func SetSpeed(speed: Float) -> Void {
        NightSceneServices.Get().SceneManager().SetSpeed(speed);
    }

    /// Switch camera mode.
    public static func SetCameraMode(mode: NightSceneCameraMode) -> Void {
        NightSceneServices.Get().SceneManager().SetCameraMode(mode);
    }

    /// Cycle to the next cinematic camera preset.
    public static func NextCameraPreset() -> Void {
        NightSceneServices.Get().CameraController().NextPreset();
    }

    // ============================================================
    //  QUERY
    // ============================================================

    /// Check if a scene is currently active.
    public static func IsSceneActive() -> Bool {
        return NightSceneServices.Get().SceneManager().IsSceneActive();
    }

    /// Get the number of registered animations.
    public static func GetAnimationCount() -> Int32 {
        return NightSceneServices.Get().AnimRegistry().GetCount();
    }

    /// Get all registered pack names.
    public static func GetPackNames() -> array<String> {
        return NightSceneServices.Get().AnimRegistry().GetPackNames();
    }

    /// Query animations by tags.
    public static func QueryAnimations(tags: array<String>, actorCount: Int32) -> array<ref<NightSceneAnimationDef>> {
        let emptyGenders: array<NightSceneGender>;
        return NightSceneServices.Get().AnimRegistry().Query(tags, actorCount, emptyGenders, false);
    }

    /// Enable or disable an animation for random selection, by ID.
    /// Disabled animations remain visible to QueryAnimations (for the CET
    /// animation browser UI) but are excluded by GetRandom.
    public static func SetAnimationEnabled(id: String, enabled: Bool) -> Bool {
        return NightSceneServices.Get().AnimRegistry().SetAnimationEnabled(id, enabled);
    }

    // ============================================================
    //  ANIMATION REGISTRATION (for pack mods)
    // ============================================================

    /// Register a new animation definition.
    public static func RegisterAnimation(def: ref<NightSceneAnimationDef>) -> Bool {
        return NightSceneServices.Get().AnimRegistry().RegisterAnimation(def);
    }

    /// Unregister all animations from a pack.
    public static func UnregisterPack(packName: String) -> Int32 {
        return NightSceneServices.Get().AnimRegistry().UnregisterPack(packName);
    }

    /// Get the entity path of the active scene's workspot (for CET to spawn).
    public static func GetActiveSceneEntityPath() -> String {
        let mgr = NightSceneServices.Get().SceneManager();
        let scene = mgr.GetActiveScene();
        if IsDefined(scene) && IsDefined(scene.animDef) && IsDefined(scene.animDef.workspot) {
            return scene.animDef.workspot.entityPath;
        }
        return "";
    }

    /// Get the component name of the active scene's workspot.
    public static func GetActiveSceneWorkspotComp() -> CName {
        let mgr = NightSceneServices.Get().SceneManager();
        let scene = mgr.GetActiveScene();
        if IsDefined(scene) && IsDefined(scene.animDef) && IsDefined(scene.animDef.workspot) {
            return scene.animDef.workspot.componentName;
        }
        return n"";
    }

    /// Get the animation name for a specific actor index in the current stage.
    public static func GetActiveSceneAnimName(actorIndex: Int32) -> CName {
        let mgr = NightSceneServices.Get().SceneManager();
        let scene = mgr.GetActiveScene();
        if IsDefined(scene) {
            let stage = scene.GetCurrentStage();
            if IsDefined(stage) && actorIndex < ArraySize(stage.actorAnims) {
                return stage.actorAnims[actorIndex].animName;
            }
        }
        return n"";
    }

    /// Get animation name as a String (easier for CET Lua to handle).
    public static func GetActiveSceneAnimNameStr(actorIndex: Int32) -> String {
        return NameToString(NightSceneAPI.GetActiveSceneAnimName(actorIndex));
    }

    /// Check if an actor in the active scene is the player.
    public static func IsActiveSceneActorPlayer(actorIndex: Int32) -> Bool {
        let mgr = NightSceneServices.Get().SceneManager();
        let scene = mgr.GetActiveScene();
        if IsDefined(scene) && actorIndex < ArraySize(scene.actors) {
            return scene.actors[actorIndex].isPlayer;
        }
        return false;
    }

    /// Get the number of actors in the active scene.
    public static func GetActiveSceneActorCount() -> Int32 {
        let mgr = NightSceneServices.Get().SceneManager();
        let scene = mgr.GetActiveScene();
        if IsDefined(scene) {
            return ArraySize(scene.actors);
        }
        return 0;
    }

    /// Get an actor's entity from the active scene by index.
    public static func GetActiveSceneActor(actorIndex: Int32) -> ref<GameObject> {
        let mgr = NightSceneServices.Get().SceneManager();
        let scene = mgr.GetActiveScene();
        if IsDefined(scene) && actorIndex < ArraySize(scene.actors) {
            return scene.actors[actorIndex].entity;
        }
        return null;
    }

    /// Notify the framework that the workspot entity has been spawned by CET.
    /// CET calls this after exEntitySpawner.Spawn + FindEntityByID succeeds.
    public static func NotifyWorkspotReady(workspotEntity: ref<GameObject>) -> Void {
        let mgr = NightSceneServices.Get().SceneManager();
        mgr.SetWorkspotEntityFromCET(workspotEntity);
    }

    /// Hide Player V for a scene: make invisible, untargetable, lock movement.
    /// No teleporting -- V stays at current position but can't be seen or targeted.
    public static func HidePlayerForScene() -> Void {
        let gi = GetGameInstance();
        let player = GetPlayer(gi);
        if !IsDefined(player) { return; }

        // Make V invisible
        player.SetInvisible(true);

        // Block detection by AI
        player.PromoteOpticalCamoEffectorToCompletelyBlocking();

        // Remove V from all hostile threat lists
        let trackerComp = player.GetTargetTrackerComponent();
        if IsDefined(trackerComp) {
            let threats = trackerComp.GetHostileThreats(false);
            let i: Int32 = 0;
            while i < ArraySize(threats) {
                let hostileEntity = threats[i].entity as ScriptedPuppet;
                if IsDefined(hostileEntity) {
                    let hostileTracker = hostileEntity.GetTargetTrackerComponent();
                    if IsDefined(hostileTracker) {
                        hostileTracker.DeactivateThreat(player);
                    }
                }
                i += 1;
            }
        }

        // Lock movement
        StatusEffectHelper.ApplyStatusEffect(player, t"BaseStatusEffect.intomovementLockActive");

        LogChannel(n"NightScene", "Player hidden for scene (invisible + untargetable)");
    }

    /// Restore Player V after a scene: make visible again, unlock movement.
    public static func RestorePlayerFromScene() -> Void {
        let gi = GetGameInstance();
        let player = GetPlayer(gi) as PlayerPuppet;
        if !IsDefined(player) { return; }

        player.SetInvisible(false);
        StatusEffectHelper.RemoveStatusEffect(player, t"BaseStatusEffect.intomovementLockActive");

        // Also trigger defeat-specific cleanup (enemy unfreeze after grace period)
        NightSceneDefeatHelper.RestoreFromDefeat(player);

        LogChannel(n"NightScene", "Player restored from scene");
    }

    /// Get the entity reference for an active scene actor by index.
    /// Used by NakedNPC integration to get actor entities for stripping.
    public static func GetSceneActor(actorIndex: Int32) -> ref<GameObject> {
        let mgr = NightSceneServices.Get().SceneManager();
        let scene = mgr.GetActiveScene();
        if !IsDefined(scene) || actorIndex >= ArraySize(scene.actors) {
            return null;
        }
        return scene.actors[actorIndex].entity;
    }

    /// Strip clothing from an active scene actor by index.
    /// Uses Codeware's GetComponents() to find and hide garment meshes.
    public static func StripSceneActor(actorIndex: Int32) -> Void {
        let mgr = NightSceneServices.Get().SceneManager();
        let scene = mgr.GetActiveScene();
        if !IsDefined(scene) || actorIndex >= ArraySize(scene.actors) {
            LogChannel(n"NightScene", "StripSceneActor: no scene or invalid index");
            return;
        }

        let entity = scene.actors[actorIndex].entity;
        if !IsDefined(entity) {
            LogChannel(n"NightScene", "StripSceneActor: no entity for actor " + IntToString(actorIndex));
            return;
        }

        NightSceneAPI.StripEntity(entity);
    }

    /// Strip CLOTHING from an entity while keeping body/skin mesh.
    /// t0_ = nude body (torso+shoulders+arms) - KEEP
    /// s0_ = feet body mesh - KEEP
    /// h0_/hx_/ht_/he_/hh_ = head/face/hair - KEEP
    /// a0_ = arm cyberware/nails - KEEP
    /// i0_ = inner body - KEEP
    /// Everything else with clothing prefixes = STRIP
    public static func StripEntity(entity: ref<GameObject>) -> Void {
        let components = entity.GetComponents();
        let stripped: Int32 = 0;
        let i: Int32 = 0;
        while i < ArraySize(components) {
            let comp = components[i];
            let compName = NameToString(comp.GetName());
            let className = NameToString(comp.GetClassName());

            if StrContains(className, "Mesh") {
                let isClothing = false;

                // STRIP these (clothing layers):
                if StrBeginsWith(compName, "t1_") || StrBeginsWith(compName, "t2_") {
                    isClothing = true; // torso clothing (shirt, jacket)
                }
                if StrBeginsWith(compName, "l0_") || StrBeginsWith(compName, "l1_") {
                    isClothing = true; // legs (pants, tights, underwear)
                }
                if StrBeginsWith(compName, "s1_") {
                    isClothing = true; // shoes
                }
                if StrBeginsWith(compName, "h1_") || StrBeginsWith(compName, "h2_") {
                    isClothing = true; // headwear (hats, glasses)
                }
                if StrBeginsWith(compName, "i1_") {
                    isClothing = true; // accessories (chokers, jewelry)
                }
                if StrBeginsWith(compName, "o1_") {
                    isClothing = true; // outfit overlay
                }
                if StrBeginsWith(compName, "g1_") {
                    isClothing = true; // gloves
                }

                // All body mesh prefixes are implicitly KEPT by not being in the list above:
                // t0_ (body), s0_ (feet), h0_/hx_/ht_/he_/hh_ (head/face/hair), a0_ (arms), i0_ (inner)

                if isClothing {
                    comp.Toggle(false);
                    stripped += 1;
                }
            }
            i += 1;
        }
        LogChannel(n"NightScene", "Stripped " + IntToString(stripped) + " clothing items (kept body)");
    }

    /// Detect NPC gender: returns 1 for Male, 2 for Female.
    public static func DetectEntityGender(entity: ref<GameObject>) -> Int32 {
        let gender = NightSceneServices.Get().ActorController().DetectGender(entity);
        return EnumInt(gender);
    }

    /// Register an AMM-compatible animation with flat parameters (easy to call from CET Lua).
    /// @param id            Unique animation ID (e.g. "mypack_kiss_01")
    /// @param packName      Pack/category name (e.g. "Agustin Poses")
    /// @param displayName   Human-readable name (e.g. "Kiss Scene 01")
    /// @param entityPath    Depot path to the .ent file (e.g. "cyan\\agustin\\poses.ent")
    /// @param animFemale    Animation name for female rig (empty string if none)
    /// @param animMale      Animation name for male rig (empty string if none)
    /// @param tags          Comma-separated tags (e.g. "standing,interaction,kiss")
    /// @return              True if registration succeeded
    public static func RegisterAMMAnimation(
        id: String,
        packName: String,
        displayName: String,
        entityPath: String,
        animFemale: String,
        animMale: String,
        tags: String
    ) -> Bool {
        let def = new NightSceneAnimationDef();
        def.id = id;
        def.packName = packName;
        def.displayName = displayName;
        def.supportsFirstPerson = true;
        def.useWorkspot = true;
        def.enabled = true;

        // Set up workspot definition
        def.workspot = new NightSceneWorkspotDef();
        def.workspot.entityPath = entityPath;
        def.workspot.componentName = n"amm_workspot_collab";

        // Determine actor count and gender tags
        let hasFemale = NotEquals(animFemale, "");
        let hasMale = NotEquals(animMale, "");

        if hasFemale && hasMale {
            // Two-actor paired animation
            def.actorCount = 2;
            ArrayPush(def.genderTags, NightSceneGender.Female);
            ArrayPush(def.genderTags, NightSceneGender.Male);

            // Add rig mappings to workspot
            ArrayPush(def.workspot.rigTypes, "Woman Average");
            ArrayPush(def.workspot.animNames, animFemale);
            ArrayPush(def.workspot.rigTypes, "Man Average");
            ArrayPush(def.workspot.animNames, animMale);
        } else {
            // Single-actor animation
            def.actorCount = 1;
            if hasFemale {
                ArrayPush(def.genderTags, NightSceneGender.Female);
                ArrayPush(def.workspot.rigTypes, "Woman Average");
                ArrayPush(def.workspot.animNames, animFemale);
            } else {
                ArrayPush(def.genderTags, NightSceneGender.Male);
                ArrayPush(def.workspot.rigTypes, "Man Average");
                ArrayPush(def.workspot.animNames, animMale);
            }
        }

        // Build a single stage from the workspot anims
        let stage = new NightSceneStage();
        stage.label = displayName;
        stage.speed = 1.0;
        stage.durationOverride = 30.0;
        stage.transitionIn = NightSceneTransition.Instant;

        // Add actor anims to the stage
        if hasFemale {
            let femAnim = new NightSceneActorAnim();
            femAnim.animName = StringToName(animFemale);
            femAnim.role = NightSceneActorRole.Subject;
            femAnim.duration = 30.0;
            femAnim.positionOffset = new Vector4(0.0, 0.0, 0.0, 0.0);
            femAnim.rotationOffset = new EulerAngles();
            ArrayPush(stage.actorAnims, femAnim);
        }
        if hasMale {
            let maleAnim = new NightSceneActorAnim();
            maleAnim.animName = StringToName(animMale);
            if hasFemale {
                maleAnim.role = NightSceneActorRole.Partner;
            } else {
                maleAnim.role = NightSceneActorRole.Subject;
            }
            maleAnim.duration = 30.0;
            maleAnim.positionOffset = new Vector4(0.0, 0.0, 0.0, 0.0);
            maleAnim.rotationOffset = new EulerAngles();
            ArrayPush(stage.actorAnims, maleAnim);
        }

        ArrayPush(def.stages, stage);

        // Parse comma-separated tags
        let tagStart: Int32 = 0;
        let tagLen: Int32 = StrLen(tags);
        let idx: Int32 = 0;
        while idx < tagLen {
            if Equals(StrMid(tags, idx, 1), ",") {
                let tag = StrMid(tags, tagStart, idx - tagStart);
                if NotEquals(tag, "") {
                    ArrayPush(def.tags, tag);
                }
                tagStart = idx + 1;
            }
            idx += 1;
        }
        // Last tag (after final comma or the whole string)
        if tagStart < tagLen {
            let lastTag = StrMid(tags, tagStart, tagLen - tagStart);
            if NotEquals(lastTag, "") {
                ArrayPush(def.tags, lastTag);
            }
        }

        return NightSceneServices.Get().AnimRegistry().RegisterAnimation(def);
    }

    // ============================================================
    //  EVENT SYSTEM (for mod integration)
    // ============================================================

    /// Subscribe to a framework event.
    public static func Subscribe(eventName: CName, callback: ref<NightSceneCallback>) -> Void {
        NightSceneServices.Get().EventBus().Subscribe(eventName, callback);
    }

    /// Unsubscribe from a framework event.
    public static func Unsubscribe(eventName: CName, callback: ref<NightSceneCallback>) -> Void {
        NightSceneServices.Get().EventBus().Unsubscribe(eventName, callback);
    }

    // ============================================================
    //  CONFIGURATION
    // ============================================================

    /// Get the current configuration.
    public static func GetConfig() -> ref<NightSceneConfig> {
        return NightSceneServices.Get().SceneManager().GetConfig();
    }

    /// Apply updated configuration.
    public static func SetConfig(config: ref<NightSceneConfig>) -> Void {
        NightSceneServices.Get().SceneManager().SetConfig(config);
    }

    // ============================================================
    //  INDIVIDUAL CONFIG SETTERS (for CET Lua bridge)
    // ============================================================

    public static func SetEnabled(value: Bool) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().enabled = value;
    }

    public static func SetDefeatEnabled(value: Bool) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().defeatEnabled = value;
    }

    public static func SetDefeatHealthThreshold(value: Float) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().defeatHealthThreshold = value;
        // Commented out: this is called every frame the settings menu is open
        // (via Config.SyncToRedscript), which spammed the log continuously.
        // LogChannel(n"NightScene", "Defeat threshold set to " + FloatToString(value * 100.0) + "%");
    }

    public static func SetPlayerPosition(position: NightScenePlayerPosition) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().playerPosition = position;
    }

    public static func SetNpcInteractionEnabled(value: Bool) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().npcInteractionEnabled = value;
    }

    public static func SetDefaultSpeed(value: Float) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().defaultSpeed = value;
    }

    public static func SetStripEquipment(value: Bool) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().stripEquipment = value;
    }

    public static func SetAutoAdvanceStages(value: Bool) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().autoAdvanceStages = value;
    }

    public static func SetDefeatGracePeriod(value: Float) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().defeatGracePeriod = value;
    }

    public static func SetDefeatCooldown(value: Float) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().defeatCooldown = value;
    }

    public static func SetDefeatMoneyLoss(value: Float) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().defeatMoneyLoss = value;
    }

    public static func SetDefeatMoneyLossIsPercent(value: Bool) -> Void {
        NightSceneServices.Get().SceneManager().GetConfig().defeatMoneyLossIsPercent = value;
    }

    // ============================================================
    //  PENDING WORKSPOT SPAWN FLAG (for Lua-side workspot spawning)
    // ============================================================
    // Set by EVERY scene start -- defeat, NPC defeat, and normal hotkey
    // interaction alike. The Lua onUpdate poller watches this and calls
    // WorkspotSpawner.SpawnAndPlay() when it flips true.

    public static func SetPendingWorkspotSpawn(value: Bool) -> Void {
        NightSceneServices.Get().SceneManager().SetPendingWorkspotSpawn(value);
    }

    public static func HasPendingWorkspotSpawn() -> Bool {
        return NightSceneServices.Get().SceneManager().HasPendingWorkspotSpawn();
    }

    public static func ClearPendingWorkspotSpawn() -> Void {
        NightSceneServices.Get().SceneManager().SetPendingWorkspotSpawn(false);
    }
}
