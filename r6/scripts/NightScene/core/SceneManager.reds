// NightScene Framework - Scene Manager
// =======================================
// The central orchestrator for animation scenes.
// Manages the full lifecycle:
//   Idle -> Initializing -> Positioning -> Playing -> [Transitioning -> Playing]* -> Finishing -> Cleanup -> Idle
//
// Only one scene can be active at a time (like SexLab).
// The Scene Manager coordinates ActorController, AnimationRegistry,
// CameraController, and EventSystem.

/// Delayed callback for stage auto-advance.
public class NightSceneStageCallback extends DelayCallback {
    public let sceneManager: wref<NightSceneManager>;
    public let sceneId: Uint64;

    public func Call() -> Void {
        if IsDefined(this.sceneManager) {
            this.sceneManager.OnStageTimerExpired(this.sceneId);
        }
    }
}

/// Delayed callback for workspot entity spawn readiness check.
public class NightSceneWorkspotSpawnCallback extends DelayCallback {
    public let sceneManager: wref<NightSceneManager>;
    public let sceneId: Uint64;

    public func Call() -> Void {
        if IsDefined(this.sceneManager) {
            this.sceneManager.OnWorkspotEntityReady(this.sceneId);
        }
    }
}

/// The main scene lifecycle manager -- singleton.
public class NightSceneManager extends IScriptable {

    // Current active scene (null if no scene is running)
    private let m_activeScene: ref<NightSceneInstance>;

    // References to subsystems
    private let m_actorCtrl: ref<NightSceneActorController>;
    private let m_eventBus: ref<NightSceneEventBus>;
    private let m_registry: ref<NightSceneAnimRegistry>;
    private let m_cameraCtrl: ref<NightSceneCameraController>;

    // Configuration
    private let m_config: ref<NightSceneConfig>;

    // Delay system callback ID for stage timing
    private let m_stageDelayId: DelayID;

    // Set whenever a scene starts (defeat, NPC defeat, or normal interaction)
    // to tell the Lua side it needs to spawn the workspot entity.
    private let m_pendingWorkspotSpawn: Bool;

    // Set when the animation or stage changes mid-scene, to tell the Lua side
    // to re-point the EXISTING actors at the new clips. Distinct from
    // m_pendingWorkspotSpawn, which means "build the whole scene from scratch".
    private let m_pendingWorkspotUpdate: Bool;

    // Game instance reference
    private let m_gameInstance: GameInstance;

    // Workspot entity reference (spawned for workspot-based animations)
    private let m_workspotEntity: wref<GameObject>;
    private let m_workspotEntityID: EntityID;

    /// Initialize the manager and wire up subsystem references.
    public func Initialize() -> Void {
        this.m_actorCtrl = NightSceneServices.Get().ActorController();
        this.m_eventBus = NightSceneServices.Get().EventBus();
        this.m_registry = NightSceneServices.Get().AnimRegistry();
        this.m_cameraCtrl = NightSceneServices.Get().CameraController();
        this.m_config = NightSceneConfig.CreateDefault();
        LogChannel(n"NightScene", "Scene Manager initialized");
    }

    /// Update configuration (called from CET when settings change).
    public func SetConfig(config: ref<NightSceneConfig>) -> Void {
        this.m_config = config;
    }

    public func GetConfig() -> ref<NightSceneConfig> {
        return this.m_config;
    }

    /// Check if a scene is currently active.
    public func IsSceneActive() -> Bool {
        return IsDefined(this.m_activeScene) && !Equals(EnumInt(this.m_activeScene.state), EnumInt(NightSceneState.Idle));
    }

    /// Get the active scene instance (may be null).
    public func GetActiveScene() -> ref<NightSceneInstance> {
        return this.m_activeScene;
    }

    // Pending workspot spawn flag
    public func SetPendingWorkspotSpawn(value: Bool) -> Void {
        this.m_pendingWorkspotSpawn = value;
    }

    public func HasPendingWorkspotSpawn() -> Bool {
        return this.m_pendingWorkspotSpawn;
    }

    /// Read-and-clear: CET polls this after an animation or stage change.
    public func ConsumePendingWorkspotUpdate() -> Bool {
        let pending = this.m_pendingWorkspotUpdate;
        this.m_pendingWorkspotUpdate = false;
        return pending;
    }

    // ============================================================
    //  SCENE LIFECYCLE
    // ============================================================

    /// Start a new scene with the given animation and actors.
    /// This is the main entry point called by the public API, hotkeys, or hooks.
    ///
    /// @param animDef       The animation definition to play
    /// @param actors        Game entities participating (index 0 = subject/player)
    /// @param triggerSource How the scene was initiated
    /// @param scenePos      World position for the scene root (uses player pos if zero)
    /// @return              True if the scene started successfully
    public func StartScene(
        animDef: ref<NightSceneAnimationDef>,
        actors: array<ref<GameObject>>,
        triggerSource: NightSceneTriggerSource,
        scenePos: Vector4
    ) -> Bool {
        // Validate preconditions
        if !this.m_config.enabled {
            LogChannel(n"NightScene", "Framework is disabled");
            return false;
        }

        if this.IsSceneActive() {
            LogChannel(n"NightScene", "A scene is already active");
            return false;
        }

        if !IsDefined(animDef) {
            LogChannel(n"NightScene", "ERROR: Animation definition is null");
            return false;
        }

        if ArraySize(actors) != animDef.actorCount {
            LogChannel(n"NightScene", "ERROR: Actor count mismatch. Expected " + IntToString(animDef.actorCount) + ", got " + IntToString(ArraySize(actors)));
            return false;
        }

        // Create scene instance
        let scene = new NightSceneInstance();
        scene.sceneId = this.m_registry.GenerateSceneId();
        scene.state = NightSceneState.Initializing;
        scene.animDef = animDef;
        scene.currentStageIndex = -1; // Will be set to 0 when playing starts
        scene.triggerSource = triggerSource;
        scene.speed = this.m_config.defaultSpeed;
        scene.cameraMode = this.m_config.defaultCameraMode;

        // Use provided position or player position
        if Vector4.IsZero(scenePos) {
            scene.scenePosition = actors[0].GetWorldPosition();
        } else {
            scene.scenePosition = scenePos;
        }
        scene.sceneOrientation = actors[0].GetWorldOrientation();

        // Cache game instance
        this.m_gameInstance = actors[0].GetGame();

        // Initialize actor states
        let i: Int32 = 0;
        while i < ArraySize(actors) {
            let role: NightSceneActorRole;
            if i == 0 {
                role = NightSceneActorRole.Subject;
            } else {
                if i == 1 {
                    role = NightSceneActorRole.Partner;
                } else {
                    role = NightSceneActorRole.Extra;
                }
            }
            let actorState = this.m_actorCtrl.InitActorState(actors[i], role);
            ArrayPush(scene.actors, actorState);
            i += 1;
        }

        this.m_activeScene = scene;
        this.m_pendingWorkspotUpdate = false;

        LogChannel(n"NightScene", "Starting scene " + ToString(scene.sceneId) + " with animation: " + animDef.id);

        // Begin the setup pipeline
        this.SetupScene();
        return true;
    }

    /// Phase 2: Prepare actors (disable AI, strip equipment, position).
    /// If the animation uses workspots, spawn the workspot entity first.
    private func SetupScene() -> Void {
        let scene = this.m_activeScene;
        scene.state = NightSceneState.Positioning;

        let i: Int32 = 0;
        while i < ArraySize(scene.actors) {
            let actor = scene.actors[i];

            // Disable AI on NPCs
            this.m_actorCtrl.DisableAI(actor);

            // Lock player controls
            if actor.isPlayer {
                let player = actor.entity as PlayerPuppet;
                if IsDefined(player) {
                    this.m_actorCtrl.LockPlayerControls(player);
                }
            }

            // Stripping is handled by NakedNPC via the Lua workspot_spawner
            // (30 frame delay after animation starts). No built-in stripping here.

            i += 1;
        }

        // If using workspot animations, spawn the workspot entity
        if scene.animDef.useWorkspot && IsDefined(scene.animDef.workspot) {
            this.SpawnWorkspotEntity(scene);
        }

        // Start playing the first stage
        this.AdvanceToStage(0);
    }

    /// Spawn a workspot entity at the scene position for workspot-based animations.
    /// Uses Codeware's DynamicEntitySystem to create the entity from the .ent path.
    private func SpawnWorkspotEntity(scene: ref<NightSceneInstance>) -> Void {
        // TODO: Workspot entity spawning needs to happen from CET Lua
        // using exEntitySpawner.Spawn() since ResRef can't be constructed
        // from runtime strings in Redscript.
        LogChannel(n"NightScene", "Workspot spawn requested for: " + scene.animDef.workspot.entityPath);
        LogChannel(n"NightScene", "NOTE: Workspot spawning from Redscript not yet implemented - use CET");

        // The entity spawns asynchronously. We register a listener to get notified.
        // For now, we use a short delay to allow the entity to spawn before playing.
        // TODO: Use DynamicEntitySystem.RegisterListener for proper async handling.
        let gi = this.m_gameInstance;
        let delaySys = GameInstance.GetDelaySystem(gi);
        let spawnCallback = new NightSceneWorkspotSpawnCallback();
        spawnCallback.sceneManager = this;
        spawnCallback.sceneId = scene.sceneId;
        delaySys.DelayCallback(spawnCallback, 0.5, false);

        LogChannel(n"NightScene", "Spawning workspot entity at scene position");
    }

    /// Called by CET Lua after it spawns the workspot entity via exEntitySpawner.
    public func SetWorkspotEntityFromCET(entity: ref<GameObject>) -> Void {
        if !IsDefined(this.m_activeScene) {
            return;
        }
        this.m_workspotEntity = entity;
        this.m_activeScene.workspotReady = true;
        LogChannel(n"NightScene", "Workspot entity received from CET");
    }

    /// Called after workspot entity spawn delay. Caches the entity reference.
    public func OnWorkspotEntityReady(sceneId: Uint64) -> Void {
        if !IsDefined(this.m_activeScene) || this.m_activeScene.sceneId != sceneId {
            return;
        }

        let dynEntitySys = GameInstance.GetDynamicEntitySystem();
        this.m_workspotEntity = dynEntitySys.GetEntity(this.m_workspotEntityID) as GameObject;

        if IsDefined(this.m_workspotEntity) {
            this.m_activeScene.workspotReady = true;
            LogChannel(n"NightScene", "Workspot entity ready");
        } else {
            LogChannel(n"NightScene", "WARN: Workspot entity failed to spawn, falling back to direct animation");
        }
    }

    /// Destroy the spawned workspot entity during cleanup.
    private func DestroyWorkspotEntity() -> Void {
        let dynEntitySys = GameInstance.GetDynamicEntitySystem();
        dynEntitySys.DeleteEntity(this.m_workspotEntityID);
        this.m_workspotEntity = null;
        LogChannel(n"NightScene", "Destroyed workspot entity");
    }

    /// Advance to a specific stage index.
    private func AdvanceToStage(stageIndex: Int32) -> Void {
        let scene = this.m_activeScene;

        if stageIndex >= scene.GetStageCount() {
            // No more stages -- finish the scene
            this.FinishScene();
            return;
        }

        // If transitioning between stages, handle the transition
        if scene.currentStageIndex >= 0 {
            scene.state = NightSceneState.Transitioning;
            let nextStage = scene.animDef.stages[stageIndex];

            // Handle transition type
            // VERIFY: Actual transition implementation (fade, cut, etc.)
            // For now, instant transition
            if Equals(EnumInt(nextStage.transitionIn), EnumInt(NightSceneTransition.BlackOut)) {
                // TODO: Trigger screen fade via ink system
                LogChannel(n"NightScene", "BlackOut transition (TODO: implement fade)");
            }
        }

        scene.currentStageIndex = stageIndex;
        scene.state = NightSceneState.Playing;
        scene.stageStartTime = EngineTime.ToFloat(GameInstance.GetSimTime(this.m_gameInstance));

        let stage = scene.GetCurrentStage();

        LogChannel(n"NightScene", "Playing stage " + IntToString(stageIndex) + ": " + stage.label);

        // Position and play animations on each actor
        let useWorkspot = scene.animDef.useWorkspot && IsDefined(scene.animDef.workspot);

        let i: Int32 = 0;
        while i < ArraySize(scene.actors) {
            let actor = scene.actors[i];

            // Find the matching actor animation in this stage
            if i < ArraySize(stage.actorAnims) {
                let animData = stage.actorAnims[i];

                // Position actor according to animation offset
                this.m_actorCtrl.PositionActorForAnim(actor, scene.scenePosition, scene.sceneOrientation, animData);

                if useWorkspot && IsDefined(this.m_workspotEntity) {
                    // Workspot-based playback (AMM-compatible)
                    this.m_actorCtrl.PlayWorkspotAnimation(actor, this.m_workspotEntity, animData.animName);
                } else {
                    // Direct animation playback (fallback)
                    this.m_actorCtrl.PlayAnimation(actor, animData.animName, scene.speed * stage.speed);
                }
            }

            i += 1;
        }

        // Set up camera for this stage
        this.m_cameraCtrl.ApplySceneCamera(scene);

        // Dispatch stage event
        if scene.currentStageIndex == 0 {
            this.m_eventBus.DispatchSceneEvent(n"OnSceneStart", scene);
        } else {
            this.m_eventBus.DispatchSceneEvent(n"OnStageChange", scene);
        }

        // Set up auto-advance timer if configured
        if this.m_config.autoAdvanceStages {
            let duration = stage.GetDuration();
            if duration > 0.0 {
                let callback = new NightSceneStageCallback();
                callback.sceneManager = this;
                callback.sceneId = scene.sceneId;
                let delaySys = GameInstance.GetDelaySystem(this.m_gameInstance);
                this.m_stageDelayId = delaySys.DelayCallback(callback, duration, false);
            }
        }
    }

    /// Called when a stage timer expires -- auto-advance to next stage.
    public func OnStageTimerExpired(sceneId: Uint64) -> Void {
        if !IsDefined(this.m_activeScene) || this.m_activeScene.sceneId != sceneId {
            return; // Scene was cancelled or a different scene is running
        }

        if this.m_activeScene.IsLastStage() {
            this.FinishScene();
        } else {
            this.AdvanceToStage(this.m_activeScene.currentStageIndex + 1);
        }
    }

    /// Manually advance to the next stage (e.g. player pressed a key).
    public func NextStage() -> Void {
        if !this.IsSceneActive() {
            return;
        }

        // Cancel any pending auto-advance timer
        this.CancelStageTimer();

        let nextIndex = this.m_activeScene.currentStageIndex + 1;
        this.AdvanceToStage(nextIndex);

        // Only flag a re-point if a stage actually remained -- past the last
        // stage AdvanceToStage finishes the scene, and there is nothing left
        // to point the actors at.
        if this.IsSceneActive() {
            this.m_pendingWorkspotUpdate = true;
        }
    }

    /// Manually go back to the previous stage.
    public func PreviousStage() -> Void {
        if !this.IsSceneActive() {
            return;
        }

        this.CancelStageTimer();

        let prevIndex = this.m_activeScene.currentStageIndex - 1;
        if prevIndex >= 0 {
            this.AdvanceToStage(prevIndex);
            this.m_pendingWorkspotUpdate = true;
        }
    }

    /// Swap the active animation without tearing the scene down.
    ///
    /// Only animations that share the current one's workspot entity AND
    /// component can be swapped in, because the actors are already standing in
    /// that workspot -- anything else would need a full respawn. Pairing
    /// families (MF / FF / MBF) are never crossed either: those differ in which
    /// rig occupies which slot, so switching across them would hand an actor a
    /// clip built for a different skeleton.
    ///
    /// Returns false when there's nothing compatible to switch to.
    public func CycleAnimation(direction: Int32) -> Bool {
        if !this.IsSceneActive() || direction == 0 {
            return false;
        }

        let scene = this.m_activeScene;
        if !IsDefined(scene.animDef) || !IsDefined(scene.animDef.workspot) {
            return false;
        }

        let candidates = this.m_registry.GetByPack(scene.animDef.packName);
        let compatible: array<ref<NightSceneAnimationDef>>;
        let i: Int32 = 0;
        while i < ArraySize(candidates) {
            let candidate = candidates[i];
            if candidate.enabled && candidate.actorCount == scene.animDef.actorCount
                && candidate.useWorkspot && IsDefined(candidate.workspot)
                && Equals(candidate.workspot.entityPath, scene.animDef.workspot.entityPath)
                && Equals(candidate.workspot.componentName, scene.animDef.workspot.componentName)
                && NightSceneManager.SamePairingFamily(scene.animDef.id, candidate.id) {
                ArrayPush(compatible, candidate);
            }
            i += 1;
        }

        if ArraySize(compatible) < 2 {
            return false;
        }

        let current: Int32 = -1;
        i = 0;
        while i < ArraySize(compatible) {
            if Equals(compatible[i].id, scene.animDef.id) {
                current = i;
                break;
            }
            i += 1;
        }
        if current < 0 {
            return false;
        }

        let next: Int32 = current + direction;
        if next >= ArraySize(compatible) {
            next = 0;
        }
        if next < 0 {
            next = ArraySize(compatible) - 1;
        }

        scene.animDef = compatible[next];
        scene.currentStageIndex = 0;
        scene.stageStartTime = EngineTime.ToFloat(GameInstance.GetSimTime(this.m_gameInstance));
        this.m_pendingWorkspotUpdate = true;

        LogChannel(n"NightScene", "Animation switched -> " + scene.animDef.id);
        return true;
    }

    /// Do two animation IDs belong to the same pairing family? IDs are built by
    /// the AMM loader as "<pack>_<family>_<name>", so the family marker is an
    /// infix. An ID with no marker only matches itself.
    public static func SamePairingFamily(currentId: String, candidateId: String) -> Bool {
        if StrContains(currentId, "_mf_") {
            return StrContains(candidateId, "_mf_");
        }
        if StrContains(currentId, "_ff_") {
            return StrContains(candidateId, "_ff_");
        }
        if StrContains(currentId, "_mbf_") {
            return StrContains(candidateId, "_mbf_");
        }
        return Equals(candidateId, currentId);
    }

    /// Adjust the playback speed of the current scene.
    public func SetSpeed(speed: Float) -> Void {
        if !this.IsSceneActive() {
            return;
        }

        this.m_activeScene.speed = speed;

        // Re-apply animations at the new speed
        let stage = this.m_activeScene.GetCurrentStage();
        let i: Int32 = 0;
        while i < ArraySize(this.m_activeScene.actors) {
            if i < ArraySize(stage.actorAnims) {
                this.m_actorCtrl.PlayAnimation(this.m_activeScene.actors[i], stage.actorAnims[i].animName, speed * stage.speed);
            }
            i += 1;
        }

        LogChannel(n"NightScene", "Speed set to: " + FloatToString(speed));
    }

    /// Change camera mode during an active scene.
    public func SetCameraMode(mode: NightSceneCameraMode) -> Void {
        if !this.IsSceneActive() {
            return;
        }
        this.m_activeScene.cameraMode = mode;
        this.m_cameraCtrl.ApplySceneCamera(this.m_activeScene);
    }

    // -------------------------------------------------------
    //  SCENE END / CLEANUP
    // -------------------------------------------------------

    /// Gracefully finish the current scene (plays finish stage if any, then cleans up).
    public func FinishScene() -> Void {
        if !IsDefined(this.m_activeScene) {
            return;
        }

        let scene = this.m_activeScene;
        scene.state = NightSceneState.Finishing;

        LogChannel(n"NightScene", "Finishing scene " + ToString(scene.sceneId));

        this.CancelStageTimer();
        this.CleanupScene();
    }

    /// Immediately cancel the current scene (e.g. player interrupted it).
    public func CancelScene() -> Void {
        if !IsDefined(this.m_activeScene) {
            return;
        }

        LogChannel(n"NightScene", "Cancelling scene " + ToString(this.m_activeScene.sceneId));

        this.CancelStageTimer();
        this.CleanupScene();
    }

    /// Internal cleanup: restore all actors, reset camera, dispatch end event.
    private func CleanupScene() -> Void {
        let scene = this.m_activeScene;
        scene.state = NightSceneState.Cleanup;

        // Restore camera
        this.m_cameraCtrl.RestoreCamera();

        // Cleanup all actors
        let i: Int32 = 0;
        while i < ArraySize(scene.actors) {
            this.m_actorCtrl.CleanupActor(scene.actors[i]);
            i += 1;
        }

        // Destroy workspot entity if one was spawned
        if IsDefined(this.m_workspotEntity) {
            this.DestroyWorkspotEntity();
        }

        // Dispatch end event
        this.m_eventBus.DispatchSceneEvent(n"OnSceneEnd", scene);

        // Reset state
        scene.state = NightSceneState.Idle;
        this.m_activeScene = null;
        this.m_pendingWorkspotUpdate = false;

        LogChannel(n"NightScene", "Scene cleanup complete");
    }

    /// Cancel any pending stage timer.
    private func CancelStageTimer() -> Void {
        let delaySys = GameInstance.GetDelaySystem(this.m_gameInstance);
        if IsDefined(delaySys) {
            delaySys.CancelDelay(this.m_stageDelayId);
        }
    }
}
