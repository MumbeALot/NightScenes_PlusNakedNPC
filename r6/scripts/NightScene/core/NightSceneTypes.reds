// NightScene Framework - Core Type Definitions
// ==============================================
// All enums, structs, and data classes used across the framework.
// This file has no dependencies on other NightScene files.
//
// DEPENDENCY: Codeware (for extended scripting features)
// DEPENDENCY: ArchiveXL (for dynamic archive loading)

// ============================================================
//  ENUMS
// ============================================================

/// The overall state of a scene being managed by the framework.
enum NightSceneState {
    Idle        = 0,
    Initializing = 1,
    Positioning  = 2,
    Playing      = 3,
    Transitioning = 4,
    Finishing    = 5,
    Cleanup      = 6,
    Error        = 7
}

/// Gender tag for animation filtering.
enum NightSceneGender {
    Any     = 0,
    Male    = 1,
    Female  = 2,
    MaleBig = 3
}

/// How a scene was triggered -- used by hooks and event system.
enum NightSceneTriggerSource {
    Manual      = 0,   // Player pressed a hotkey / used the UI
    Defeat      = 1,   // Player was defeated in combat
    NPCDefeat   = 2,   // Player defeated an NPC
    Interaction = 3,   // Proximity / dialogue NPC interaction
    API         = 4    // Another mod called the public API
}

/// Camera mode during a scene.
enum NightSceneCameraMode {
    FirstPerson   = 0,
    ThirdPerson   = 1,
    Cinematic     = 2,
    Free          = 3
}

/// Player's preferred slot in a 2-actor scene. Only honored for same-gender
/// (ff) pairings -- mixed-gender (mf/mbf) animations have their slot
/// assignment locked to body type (female-rig anim is always slot 0,
/// male/big-rig anim is always slot 1), so this has no effect there.
enum NightScenePlayerPosition {
    PositionOne = 0,
    PositionTwo = 1
}

/// Actor role inside a scene (who is the "subject" vs "partner").
enum NightSceneActorRole {
    Subject  = 0,   // Typically V / the player
    Partner  = 1,   // The NPC partner
    Extra    = 2    // Additional participants (for 3+ actor scenes)
}

/// Stage transition style.
enum NightSceneTransition {
    Instant   = 0,
    CrossFade = 1,
    BlackOut  = 2
}

// ============================================================
//  DATA STRUCTURES
// ============================================================

/// Describes a single animation that can be played on one actor.
/// Multiple NightSceneActorAnim entries compose a full scene stage.
public class NightSceneActorAnim extends IScriptable {
    // The name of the animation inside the .anims / .workspot file
    public let animName: CName;

    // Path to the .anims archive resource (depot path) -- used for direct anim playback
    public let animResource: ResRef;

    // Which actor role this animation is for
    public let role: NightSceneActorRole;

    // Duration of this animation clip in seconds
    public let duration: Float;

    // Positional offset from the scene root for this actor
    public let positionOffset: Vector4;

    // Rotation offset (euler angles in degrees)
    public let rotationOffset: EulerAngles;
}

/// Describes a workspot-based animation definition.
/// This is the primary animation source for NightScene, compatible with AMM animation packs.
/// A workspot entity (.ent) references a .workspot file which contains the animation sequences.
public class NightSceneWorkspotDef extends IScriptable {
    // Path to the workspot entity file as a string (e.g. "author\\anims\\my_workspot.ent")
    // Stored as String because ResRef can't be constructed from runtime strings.
    // Convert to ResRef at spawn time if needed.
    public let entityPath: String;

    // Animation names per rig type (key = rig name like "Woman Average", value = anim name)
    // For scenes, we use the anim name that matches the actor's rig
    public let animNames: array<String>;

    // Rig types this workspot supports (parallel array with animNames)
    public let rigTypes: array<String>;

    // The workspot component name inside the entity (default: "amm_workspot_collab")
    public let componentName: CName;
}

/// A single stage in a multi-stage scene.
/// Each stage has one animation per actor.
public class NightSceneStage extends IScriptable {
    // Human-readable label (e.g. "Stage 1", "Foreplay", "Finish")
    public let label: String;

    // Animations for each actor in this stage  (index matches actor index)
    public let actorAnims: array<ref<NightSceneActorAnim>>;

    // Duration override -- if > 0, overrides individual anim durations
    public let durationOverride: Float;

    // Transition style INTO this stage
    public let transitionIn: NightSceneTransition;

    // Speed / rate multiplier (1.0 = normal)
    public let speed: Float;

    public func GetDuration() -> Float {
        // Guard against division by zero -- treat zero/negative speed as 1.0
        let safeSpeed: Float = this.speed;
        if safeSpeed <= 0.0 {
            safeSpeed = 1.0;
        }

        if this.durationOverride > 0.0 {
            return this.durationOverride / safeSpeed;
        }
        // Fall back to longest actor animation
        let maxDur: Float = 0.0;
        let i: Int32 = 0;
        while i < ArraySize(this.actorAnims) {
            if this.actorAnims[i].duration > maxDur {
                maxDur = this.actorAnims[i].duration;
            }
            i += 1;
        }
        return maxDur / safeSpeed;
    }
}

/// A complete animation definition registered with the framework.
/// Equivalent to one "animation" in SexLab -- can have multiple stages.
public class NightSceneAnimationDef extends IScriptable {
    // Unique string ID for this animation (e.g. "mymod_standing_01")
    public let id: String;

    // Human-readable name
    public let displayName: String;

    // The mod / pack that registered this animation
    public let packName: String;

    // Number of actors required
    public let actorCount: Int32;

    // Gender requirements per actor slot  (index matches actor index)
    public let genderTags: array<NightSceneGender>;

    // Freeform tags for filtering  (e.g. "standing", "lying", "aggressive")
    public let tags: array<String>;

    // Ordered list of stages
    public let stages: array<ref<NightSceneStage>>;

    // Whether this animation supports first-person camera
    public let supportsFirstPerson: Bool;

    // --- Workspot-based animation fields ---

    // If true, this animation uses the workspot system (AMM-compatible)
    // If false, uses direct AnimationControllerComponent playback
    public let useWorkspot: Bool;

    // Workspot definition (only used when useWorkspot == true)
    public let workspot: ref<NightSceneWorkspotDef>;

    // Whether this animation is eligible for random selection. Defaults to
    // true at construction (see RegisterAMMAnimation / NightSceneAnimBuilder);
    // toggled via NightSceneAPI.SetAnimationEnabled from the CET animation
    // browser UI. Disabled animations are still returned by Query() (so the
    // browser can list and re-enable them) but excluded by GetRandom().
    public let enabled: Bool;

    /// Check if this definition matches a set of filter tags (AND logic).
    public func MatchesTags(filterTags: array<String>) -> Bool {
        let i: Int32 = 0;
        while i < ArraySize(filterTags) {
            let found: Bool = false;
            let j: Int32 = 0;
            while j < ArraySize(this.tags) {
                if Equals(this.tags[j], filterTags[i]) {
                    found = true;
                }
                j += 1;
            }
            if !found {
                return false;
            }
            i += 1;
        }
        return true;
    }

    /// Check if gender requirements are met by the provided actor genders.
    public func MatchesGenders(actorGenders: array<NightSceneGender>) -> Bool {
        if ArraySize(actorGenders) != this.actorCount {
            return false;
        }
        let i: Int32 = 0;
        while i < this.actorCount {
            let required: NightSceneGender = this.genderTags[i];
            if !Equals(EnumInt(required), EnumInt(NightSceneGender.Any)) {
                if !Equals(EnumInt(required), EnumInt(actorGenders[i])) {
                    return false;
                }
            }
            i += 1;
        }
        return true;
    }
}

/// Runtime data for one actor participating in an active scene.
public class NightSceneActorState extends IScriptable {
    // Reference to the game entity (PlayerPuppet or NPCPuppet)
    public let entity: wref<GameObject>;

    // The entity's ID for safe reference
    public let entityID: EntityID;

    // Role in the current scene
    public let role: NightSceneActorRole;

    // Gender of this actor
    public let gender: NightSceneGender;

    // Saved world transform before the scene started (for restoring)
    public let savedPosition: Vector4;
    public let savedOrientation: Quaternion;

    // Whether AI was disabled for this actor
    public let aiWasDisabled: Bool;

    // Whether equipment was stripped
    public let equipmentStripped: Bool;

    // The animation component reference (cached)
    public let animComponent: wref<AnimatedComponent>;

    // Is this actor the player?
    public let isPlayer: Bool;
}

/// Full runtime state of an active scene.
public class NightSceneInstance extends IScriptable {
    // Unique scene instance ID
    public let sceneId: Uint64;

    // Current scene state
    public let state: NightSceneState;

    // The animation definition being played
    public let animDef: ref<NightSceneAnimationDef>;

    // Current stage index
    public let currentStageIndex: Int32;

    // Actors in the scene
    public let actors: array<ref<NightSceneActorState>>;

    // Scene root position (world space)
    public let scenePosition: Vector4;
    public let sceneOrientation: Quaternion;

    // How this scene was triggered
    public let triggerSource: NightSceneTriggerSource;

    // Timestamp when the current stage started
    public let stageStartTime: Float;

    // Current speed multiplier
    public let speed: Float;

    // Active camera mode
    public let cameraMode: NightSceneCameraMode;

    // --- Workspot runtime state ---

    // The spawned workspot entity ID (for cleanup)
    public let workspotEntityID: EntityID;

    // Whether the workspot entity has been spawned and is ready
    public let workspotReady: Bool;

    public func GetCurrentStage() -> ref<NightSceneStage> {
        if this.currentStageIndex >= 0 && this.currentStageIndex < ArraySize(this.animDef.stages) {
            return this.animDef.stages[this.currentStageIndex];
        }
        return null;
    }

    public func GetStageCount() -> Int32 {
        return ArraySize(this.animDef.stages);
    }

    public func IsLastStage() -> Bool {
        return this.currentStageIndex >= ArraySize(this.animDef.stages) - 1;
    }
}

/// Configuration snapshot passed around the framework.
public class NightSceneConfig extends IScriptable {
    // Master enable/disable
    public let enabled: Bool;

    // Default camera mode
    public let defaultCameraMode: NightSceneCameraMode;

    // Whether defeat scenes are enabled
    public let defeatEnabled: Bool;

    // Health threshold (0.0 - 1.0) at which defeat triggers
    public let defeatHealthThreshold: Float;

    // Whether random NPC interactions are enabled
    public let npcInteractionEnabled: Bool;

    // NPC interaction range (meters)
    public let npcInteractionRange: Float;

    // Auto-advance stages after duration expires
    public let autoAdvanceStages: Bool;

    // Default animation speed
    public let defaultSpeed: Float;

    // Strip equipment during scenes
    public let stripEquipment: Bool;

    // Which genders to include in random NPC selection
    public let npcGenderFilter: NightSceneGender;

    // Defeat: seconds before enemies become hostile again after scene ends
    public let defeatGracePeriod: Float;

    // Defeat: seconds before defeat can trigger again
    public let defeatCooldown: Float;

    // Defeat: money to deduct on defeat (0 = disabled)
    public let defeatMoneyLoss: Float;

    // Defeat: true = defeatMoneyLoss is a percentage, false = flat eddies
    public let defeatMoneyLossIsPercent: Bool;

    // Player's preferred slot in same-gender (ff) scenes -- see NightScenePlayerPosition
    public let playerPosition: NightScenePlayerPosition;

    public static func CreateDefault() -> ref<NightSceneConfig> {
        let cfg = new NightSceneConfig();
        cfg.enabled = true;
        cfg.defaultCameraMode = NightSceneCameraMode.FirstPerson;
        cfg.defeatEnabled = true;
        cfg.defeatHealthThreshold = 0.15;
        cfg.npcInteractionEnabled = true;
        cfg.npcInteractionRange = 5.0;
        cfg.autoAdvanceStages = true;
        cfg.defaultSpeed = 1.0;
        cfg.stripEquipment = true;
        cfg.npcGenderFilter = NightSceneGender.Any;
        cfg.defeatGracePeriod = 12.0;
        cfg.defeatCooldown = 30.0;
        cfg.defeatMoneyLoss = 0.0;
        cfg.defeatMoneyLossIsPercent = false;
        cfg.playerPosition = NightScenePlayerPosition.PositionOne;
        return cfg;
    }
}

/// Data passed with NightScene events.
public class NightSceneEventData extends IScriptable {
    public let sceneId: Uint64;
    public let state: NightSceneState;
    public let stageIndex: Int32;
    public let triggerSource: NightSceneTriggerSource;
    public let animId: String;
}
