// NightScene Framework - Animation Registry
// ============================================
// Central registry where animation packs register their definitions.
// Supports tag-based filtering, gender matching, and random selection.
// This is the equivalent of SexLab's animation registration system.
//
// Animation pack mods register their animations at startup by calling:
//   NightSceneAnimRegistry.GetInstance().RegisterAnimation(def);

/// Singleton registry holding all known animation definitions.
public class NightSceneAnimRegistry extends IScriptable {
    // All registered animation definitions, keyed by unique ID
    private let m_animations: array<ref<NightSceneAnimationDef>>;

    // Index of pack names for quick lookup
    private let m_packNames: array<String>;

    // Next auto-generated scene ID
    private let m_nextSceneId: Uint64;

    public func Init() -> Void {
        this.m_nextSceneId = 1u;
    }

    /// Generate a unique scene instance ID.
    public func GenerateSceneId() -> Uint64 {
        let id = this.m_nextSceneId;
        this.m_nextSceneId = Cast<Uint64>(Cast<Int32>(this.m_nextSceneId) + 1);
        return id;
    }

    // -------------------------------------------------------
    //  REGISTRATION
    // -------------------------------------------------------

    /// Register a new animation definition.
    /// Returns true if registration succeeded, false if ID already exists.
    public func RegisterAnimation(def: ref<NightSceneAnimationDef>) -> Bool {
        // Check for duplicate ID
        if this.FindById(def.id) != -1 {
            LogChannel(n"NightScene", "WARN: Animation ID already registered: " + def.id);
            return false;
        }

        // Validate
        if ArraySize(def.stages) == 0 {
            LogChannel(n"NightScene", "ERROR: Animation has no stages: " + def.id);
            return false;
        }
        if def.actorCount < 1 || def.actorCount > 5 {
            LogChannel(n"NightScene", "ERROR: Invalid actor count for: " + def.id);
            return false;
        }

        ArrayPush(this.m_animations, def);

        // Track pack name
        if !this.HasPackName(def.packName) {
            ArrayPush(this.m_packNames, def.packName);
        }

        LogChannel(n"NightScene", "Registered animation: " + def.id + " (pack: " + def.packName + ", stages: " + IntToString(ArraySize(def.stages)) + ")");
        return true;
    }

    /// Unregister all animations from a specific pack.
    public func UnregisterPack(packName: String) -> Int32 {
        let removed: Int32 = 0;
        let i: Int32 = ArraySize(this.m_animations) - 1;
        while i >= 0 {
            if Equals(this.m_animations[i].packName, packName) {
                ArrayErase(this.m_animations, i);
                removed += 1;
            }
            i -= 1;
        }
        LogChannel(n"NightScene", "Unregistered " + IntToString(removed) + " animations from pack: " + packName);
        return removed;
    }

    // -------------------------------------------------------
    //  QUERY / LOOKUP
    // -------------------------------------------------------

    /// Get total count of registered animations.
    public func GetCount() -> Int32 {
        return ArraySize(this.m_animations);
    }

    /// Get all registered pack names.
    public func GetPackNames() -> array<String> {
        return this.m_packNames;
    }

    /// Find animation by exact ID.  Returns null if not found.
    public func GetAnimationById(id: String) -> ref<NightSceneAnimationDef> {
        let idx = this.FindById(id);
        if idx >= 0 {
            return this.m_animations[idx];
        }
        return null;
    }

    /// Query animations matching ALL provided criteria.
    /// Pass empty arrays / 0 for criteria you don't care about.
    public func Query(
        tags: array<String>,
        actorCount: Int32,
        actorGenders: array<NightSceneGender>,
        requireFirstPerson: Bool
    ) -> array<ref<NightSceneAnimationDef>> {
        let results: array<ref<NightSceneAnimationDef>>;
        let i: Int32 = 0;

        while i < ArraySize(this.m_animations) {
            let def = this.m_animations[i];
            let matches: Bool = true;

            // Filter by actor count
            if actorCount > 0 && def.actorCount != actorCount {
                matches = false;
            }

            // Filter by tags
            if matches && ArraySize(tags) > 0 {
                if !def.MatchesTags(tags) {
                    matches = false;
                }
            }

            // Filter by gender
            if matches && ArraySize(actorGenders) > 0 {
                if !def.MatchesGenders(actorGenders) {
                    matches = false;
                }
            }

            // Filter by first-person support
            if matches && requireFirstPerson && !def.supportsFirstPerson {
                matches = false;
            }

            if matches {
                ArrayPush(results, def);
            }
            i += 1;
        }
        return results;
    }

    /// Get a random animation matching the criteria.
    /// Returns null if no matches found. Excludes disabled animations (see
    /// NightSceneAnimationDef.enabled) -- Query() itself does not filter on
    /// this, so the browsing UI can still list and re-enable disabled entries.
    public func GetRandom(
        tags: array<String>,
        actorCount: Int32,
        actorGenders: array<NightSceneGender>,
        requireFirstPerson: Bool
    ) -> ref<NightSceneAnimationDef> {
        let matches = this.Query(tags, actorCount, actorGenders, requireFirstPerson);

        let enabledMatches: array<ref<NightSceneAnimationDef>>;
        let i: Int32 = 0;
        while i < ArraySize(matches) {
            if matches[i].enabled {
                ArrayPush(enabledMatches, matches[i]);
            }
            i += 1;
        }

        let count = ArraySize(enabledMatches);
        if count == 0 {
            return null;
        }
        if count == 1 {
            return enabledMatches[0];
        }
        // Use simple random selection
        let idx = RandRange(0, count);
        return enabledMatches[idx];
    }

    /// Enable or disable an animation for random selection by ID.
    /// Returns false if no animation with that ID is registered.
    public func SetAnimationEnabled(id: String, enabled: Bool) -> Bool {
        let idx = this.FindById(id);
        if idx < 0 {
            return false;
        }
        this.m_animations[idx].enabled = enabled;
        return true;
    }

    /// Get all animations from a specific pack.
    public func GetByPack(packName: String) -> array<ref<NightSceneAnimationDef>> {
        let results: array<ref<NightSceneAnimationDef>>;
        let i: Int32 = 0;
        while i < ArraySize(this.m_animations) {
            if Equals(this.m_animations[i].packName, packName) {
                ArrayPush(results, this.m_animations[i]);
            }
            i += 1;
        }
        return results;
    }

    /// Get all registered animation definitions (for browsing UI).
    public func GetAll() -> array<ref<NightSceneAnimationDef>> {
        return this.m_animations;
    }

    // -------------------------------------------------------
    //  INTERNAL HELPERS
    // -------------------------------------------------------

    /// Find the index of an animation by ID. Returns -1 if not found.
    private func FindById(id: String) -> Int32 {
        let i: Int32 = 0;
        while i < ArraySize(this.m_animations) {
            if Equals(this.m_animations[i].id, id) {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    /// Check if a pack name is already tracked.
    private func HasPackName(name: String) -> Bool {
        let i: Int32 = 0;
        while i < ArraySize(this.m_packNames) {
            if Equals(this.m_packNames[i], name) {
                return true;
            }
            i += 1;
        }
        return false;
    }
}

// ============================================================
//  HELPER: Build an animation definition fluently
// ============================================================
/// Builder pattern for constructing NightSceneAnimationDef objects.
/// Makes registration from pack mods cleaner.
///
/// Usage:
///   let builder = NightSceneAnimBuilder.Create("mymod_anim_01", "My Pack");
///   builder.SetDisplayName("Standing Animation 01");
///   builder.SetActorCount(2);
///   builder.AddGenderTag(NightSceneGender.Female);
///   builder.AddGenderTag(NightSceneGender.Male);
///   builder.AddTag("standing");
///   builder.SetSupportsFirstPerson(true);
///   builder.AddStage(stage1);
///   builder.AddStage(stage2);
///   let def = builder.Build();
///   NightSceneAnimRegistry.GetInstance().RegisterAnimation(def);

public class NightSceneAnimBuilder extends IScriptable {
    private let m_def: ref<NightSceneAnimationDef>;

    public static func Create(id: String, packName: String) -> ref<NightSceneAnimBuilder> {
        let builder = new NightSceneAnimBuilder();
        builder.m_def = new NightSceneAnimationDef();
        builder.m_def.id = id;
        builder.m_def.packName = packName;
        builder.m_def.actorCount = 2;
        builder.m_def.supportsFirstPerson = false;
        builder.m_def.enabled = true;
        return builder;
    }

    public func SetDisplayName(name: String) -> ref<NightSceneAnimBuilder> {
        this.m_def.displayName = name;
        return this;
    }

    public func SetActorCount(count: Int32) -> ref<NightSceneAnimBuilder> {
        this.m_def.actorCount = count;
        return this;
    }

    public func AddGenderTag(gender: NightSceneGender) -> ref<NightSceneAnimBuilder> {
        ArrayPush(this.m_def.genderTags, gender);
        return this;
    }

    public func AddTag(tag: String) -> ref<NightSceneAnimBuilder> {
        ArrayPush(this.m_def.tags, tag);
        return this;
    }

    public func SetSupportsFirstPerson(supports: Bool) -> ref<NightSceneAnimBuilder> {
        this.m_def.supportsFirstPerson = supports;
        return this;
    }

    /// Enable workspot-based animation playback (AMM-compatible).
    /// @param entityPath The depot path to the workspot .ent file
    public func SetWorkspot(entityPath: String) -> ref<NightSceneAnimBuilder> {
        this.m_def.useWorkspot = true;
        if !IsDefined(this.m_def.workspot) {
            this.m_def.workspot = new NightSceneWorkspotDef();
            this.m_def.workspot.componentName = n"amm_workspot_collab";
        }
        this.m_def.workspot.entityPath = entityPath;
        return this;
    }

    /// Set the workspot component name (default: "amm_workspot_collab").
    public func SetWorkspotComponent(componentName: CName) -> ref<NightSceneAnimBuilder> {
        if IsDefined(this.m_def.workspot) {
            this.m_def.workspot.componentName = componentName;
        }
        return this;
    }

    /// Add a rig type mapping for the workspot animation.
    public func AddWorkspotRig(rigType: String, animName: String) -> ref<NightSceneAnimBuilder> {
        if IsDefined(this.m_def.workspot) {
            ArrayPush(this.m_def.workspot.rigTypes, rigType);
            ArrayPush(this.m_def.workspot.animNames, animName);
        }
        return this;
    }

    public func AddStage(stage: ref<NightSceneStage>) -> ref<NightSceneAnimBuilder> {
        ArrayPush(this.m_def.stages, stage);
        return this;
    }

    public func Build() -> ref<NightSceneAnimationDef> {
        return this.m_def;
    }
}

/// Helper to build a NightSceneStage.
public class NightSceneStageBuilder extends IScriptable {
    private let m_stage: ref<NightSceneStage>;

    public static func Create(label: String) -> ref<NightSceneStageBuilder> {
        let builder = new NightSceneStageBuilder();
        builder.m_stage = new NightSceneStage();
        builder.m_stage.label = label;
        builder.m_stage.speed = 1.0;
        builder.m_stage.durationOverride = 0.0;
        builder.m_stage.transitionIn = NightSceneTransition.Instant;
        return builder;
    }

    public func SetDuration(duration: Float) -> ref<NightSceneStageBuilder> {
        this.m_stage.durationOverride = duration;
        return this;
    }

    public func SetSpeed(speed: Float) -> ref<NightSceneStageBuilder> {
        this.m_stage.speed = speed;
        return this;
    }

    public func SetTransition(transition: NightSceneTransition) -> ref<NightSceneStageBuilder> {
        this.m_stage.transitionIn = transition;
        return this;
    }

    public func AddActorAnim(animName: CName, animResource: ResRef, role: NightSceneActorRole, duration: Float) -> ref<NightSceneStageBuilder> {
        let anim = new NightSceneActorAnim();
        anim.animName = animName;
        anim.animResource = animResource;
        anim.role = role;
        anim.duration = duration;
        anim.positionOffset = new Vector4(0.0, 0.0, 0.0, 0.0);
        anim.rotationOffset = new EulerAngles();
        ArrayPush(this.m_stage.actorAnims, anim);
        return this;
    }

    public func AddActorAnimWithOffset(animName: CName, animResource: ResRef, role: NightSceneActorRole, duration: Float, offset: Vector4, rotation: EulerAngles) -> ref<NightSceneStageBuilder> {
        let anim = new NightSceneActorAnim();
        anim.animName = animName;
        anim.animResource = animResource;
        anim.role = role;
        anim.duration = duration;
        anim.positionOffset = offset;
        anim.rotationOffset = rotation;
        ArrayPush(this.m_stage.actorAnims, anim);
        return this;
    }

    public func Build() -> ref<NightSceneStage> {
        return this.m_stage;
    }
}
