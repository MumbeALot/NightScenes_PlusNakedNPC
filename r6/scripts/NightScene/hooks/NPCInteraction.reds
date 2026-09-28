// NightScene Framework - NPC Interaction System
// ================================================
// Handles finding, targeting, and initiating interactions with
// street NPCs. This is the "approach random NPCs" feature.
//
// Two interaction modes:
//   1. Hotkey mode: Player presses a key while looking at / near an NPC
//   2. Proximity mode: Framework detects eligible NPCs in range
//
// The NPC finder uses the game's targeting system and entity queries
// to locate suitable NPCs.
//
// VERIFY: Entity query and targeting system APIs need verification.

// ============================================================
//  NPC FINDER - Locates eligible NPCs in the game world
// ============================================================

public abstract class NightSceneNPCFinder {

    /// Find the NPC the player is currently looking at (crosshair target).
    /// Uses a tight frontal cone search (narrower than FindNearestNPCInFront)
    /// to approximate crosshair targeting.
    public static func FindLookAtNPC(player: ref<PlayerPuppet>) -> ref<ScriptedPuppet> {
        let gi = player.GetGame();
        let playerPos = player.GetWorldPosition();
        let playerForward = player.GetWorldForward();

        // Get nearby NPCs within interaction range
        let nearbyNPCs = NightSceneNPCFinder.FindNPCsInRange(player, 5.0);

        let bestNPC: ref<ScriptedPuppet>;
        let bestDot: Float = -1.0;

        let i: Int32 = 0;
        while i < ArraySize(nearbyNPCs) {
            let npc = nearbyNPCs[i];
            let npcPos = npc.GetWorldPosition();

            let toNPC = new Vector4(
                npcPos.X - playerPos.X,
                npcPos.Y - playerPos.Y,
                npcPos.Z - playerPos.Z,
                0.0
            );

            let distance = Vector4.Length(toNPC);
            if distance > 0.01 {
                let toNPCNorm = new Vector4(
                    toNPC.X / distance,
                    toNPC.Y / distance,
                    toNPC.Z / distance,
                    0.0
                );

                let dot = Vector4.Dot(playerForward, toNPCNorm);

                // Tight cone: dot > 0.85 is roughly a 30-degree cone (crosshair area)
                if dot > 0.85 && dot > bestDot {
                    bestDot = dot;
                    bestNPC = npc;
                }
            }

            i += 1;
        }

        // If no NPC in tight cone, fall back to wider cone search
        if !IsDefined(bestNPC) {
            return NightSceneNPCFinder.FindNearestNPCInFront(player, 5.0);
        }

        return bestNPC;
    }

    /// Find the nearest NPC in front of the player (within a cone).
    public static func FindNearestNPCInFront(player: ref<PlayerPuppet>, maxDistance: Float) -> ref<ScriptedPuppet> {
        let gi = player.GetGame();
        let playerPos = player.GetWorldPosition();
        let playerForward = player.GetWorldForward();

        // Get all NPCs in range
        let nearbyNPCs = NightSceneNPCFinder.FindNPCsInRange(player, maxDistance);

        let bestNPC: ref<ScriptedPuppet>;
        let bestDot: Float = -1.0;

        let i: Int32 = 0;
        while i < ArraySize(nearbyNPCs) {
            let npc = nearbyNPCs[i];
            let npcPos = npc.GetWorldPosition();

            // Direction from player to NPC
            let toNPC = new Vector4(
                npcPos.X - playerPos.X,
                npcPos.Y - playerPos.Y,
                npcPos.Z - playerPos.Z,
                0.0
            );

            let distance = Vector4.Length(toNPC);
            if distance > 0.01 {
                // Normalize
                let toNPCNorm = new Vector4(
                    toNPC.X / distance,
                    toNPC.Y / distance,
                    toNPC.Z / distance,
                    0.0
                );

                // Dot product with player forward (1.0 = directly ahead)
                let dot = Vector4.Dot(playerForward, toNPCNorm);

                // Must be in front (dot > 0.5 is roughly a 60-degree cone)
                if dot > 0.5 && dot > bestDot {
                    bestDot = dot;
                    bestNPC = npc;
                }
            }

            i += 1;
        }

        return bestNPC;
    }

    /// Find all NPCs within a radius of the player.
    /// Uses the game's TargetingSystem with TSQ_ALL to query nearby entities,
    /// then filters for valid ScriptedPuppet NPCs.
    public static func FindNPCsInRange(player: ref<PlayerPuppet>, range: Float) -> array<ref<ScriptedPuppet>> {
        let results: array<ref<ScriptedPuppet>>;
        let gi = player.GetGame();
        let playerPos = player.GetWorldPosition();
        let targetingSys = GameInstance.GetTargetingSystem(gi);

        // Use TSQ_ALL search query with distance filter
        let searchQuery: TargetSearchQuery;
        searchQuery.maxDistance = range;
        searchQuery.includeSecondaryTargets = true;
        searchQuery.ignoreInstigator = true;

        let parts: array<TS_TargetPartInfo>;
        targetingSys.GetTargetParts(player, searchQuery, parts);

        let i: Int32 = 0;
        while i < ArraySize(parts) {
            let component = TS_TargetPartInfo.GetComponent(parts[i]);
            if IsDefined(component) {
                let entity = component.GetEntity() as ScriptedPuppet;
                if IsDefined(entity) && !entity.IsPlayer() {
                    // Check not already in results (entity may have multiple target parts)
                    let alreadyAdded: Bool = false;
                    let j: Int32 = 0;
                    while j < ArraySize(results) {
                        if results[j].GetEntityID() == entity.GetEntityID() {
                            alreadyAdded = true;
                        }
                        j += 1;
                    }

                    if !alreadyAdded {
                        // Verify distance (some search results may exceed range)
                        let dist = Vector4.Distance(playerPos, entity.GetWorldPosition());
                        if dist <= range {
                            ArrayPush(results, entity);
                        }
                    }
                }
            }
            i += 1;
        }

        LogChannel(n"NightScene", "Found " + IntToString(ArraySize(results)) + " NPCs within " + FloatToString(range) + "m");
        return results;
    }

    /// Find the nearest hostile NPC (for defeat scenarios).
    public static func FindNearestHostileNPC(player: ref<PlayerPuppet>, range: Float) -> ref<ScriptedPuppet> {
        let npcs = NightSceneNPCFinder.FindNPCsInRange(player, range);

        let bestNPC: ref<ScriptedPuppet>;
        let bestDist: Float = 99999.0;
        let playerPos = player.GetWorldPosition();

        let i: Int32 = 0;
        while i < ArraySize(npcs) {
            let npc = npcs[i];

            // Check if hostile
            // VERIFY: How to check NPC attitude/faction toward player
            let attitude = GameObject.GetAttitudeTowards(npc, player);
            if Equals(attitude, EAIAttitude.AIA_Hostile) {
                let dist = Vector4.Distance(playerPos, npc.GetWorldPosition());
                if dist < bestDist {
                    bestDist = dist;
                    bestNPC = npc;
                }
            }
            i += 1;
        }

        return bestNPC;
    }

    /// Check if an NPC is eligible for interaction.
    public static func IsNPCEligible(npc: ref<ScriptedPuppet>, config: ref<NightSceneConfig>) -> Bool {
        if !IsDefined(npc) {
            return false;
        }

        // Only actual corpses are excluded. Defeated (unconscious, still alive)
        // NPCs are eligible here too -- OnInteractionHotkey checks
        // ScriptedPuppet.IsDefeated(npc) first and routes those to the defeat
        // scene before this function is ever reached for them.
        if npc.IsDead() {
            return false;
        }

        // Gender filter
        if !Equals(EnumInt(config.npcGenderFilter), EnumInt(NightSceneGender.Any)) {
            let npcGender = NightSceneServices.Get().ActorController().DetectGender(npc);
            if !Equals(EnumInt(npcGender), EnumInt(config.npcGenderFilter)) {
                return false;
            }
        }

        // Must not be a quest-critical NPC
        // VERIFY: How to check if NPC is quest-critical
        // let isQuest = npc.IsQuestNPC() or similar

        // Must not be a child NPC
        // VERIFY: How to check NPC age/type

        return true;
    }
}

// ============================================================
//  NPC INTERACTION HANDLER - Processes interaction requests
// ============================================================

/// Handles the logic when the player initiates an interaction with an NPC.
public class NightSceneInteractionHandler extends IScriptable {

    /// Called when the player presses the interaction hotkey.
    /// Finds the target NPC and starts a scene.
    public func OnInteractionHotkey() -> Void {
        let config = NightSceneServices.Get().SceneManager().GetConfig();

        if !config.enabled || !config.npcInteractionEnabled {
            LogChannel(n"NightScene", "NPC interaction is disabled");
            return;
        }

        if NightSceneServices.Get().SceneManager().IsSceneActive() {
            LogChannel(n"NightScene", "A scene is already active");
            return;
        }

        // Get the player
        let gi = GetGameInstance();
        let player = GetPlayer(gi);

        if !IsDefined(player) {
            return;
        }

        // Find target NPC
        let targetNPC = NightSceneNPCFinder.FindLookAtNPC(player);
        if !IsDefined(targetNPC) {
            targetNPC = NightSceneNPCFinder.FindNearestNPCInFront(player, 5.0);
        }

        if !IsDefined(targetNPC) {
            LogChannel(n"NightScene", "No NPC found to interact with");
            // TODO: Show UI notification to player
            return;
        }

        // Dead NPCs (actual corpses) are never eligible for anything.
        if targetNPC.IsDead() {
            LogChannel(n"NightScene", "Target NPC is dead, not eligible");
            return;
        }

        // Defeated NPCs (game's own "unconscious, still alive" state) only ever get
        // the scene from this manual hotkey press -- there is no automatic trigger.
        if ScriptedPuppet.IsDefeated(targetNPC) {
            if !config.defeatEnabled {
                LogChannel(n"NightScene", "Defeat interactions are disabled");
                return;
            }
            NightSceneDefeatHelper.TriggerNPCDefeatScene(player, targetNPC);
            return;
        }

        // Otherwise, normal conscious-NPC interaction
        if !NightSceneNPCFinder.IsNPCEligible(targetNPC, config) {
            LogChannel(n"NightScene", "Target NPC is not eligible for interaction");
            return;
        }

        // Start the interaction
        this.StartInteraction(player, targetNPC);
    }

    /// Start an interaction scene with the given NPC.
    public func StartInteraction(player: ref<PlayerPuppet>, npc: ref<ScriptedPuppet>) -> Void {
        let registry = NightSceneServices.Get().AnimRegistry();
        let manager = NightSceneServices.Get().SceneManager();
        let actorCtrl = NightSceneServices.Get().ActorController();

        let playerGender = actorCtrl.DetectGender(player);
        let npcGender = actorCtrl.DetectGender(npc);
        let playerIsFemale = Equals(EnumInt(playerGender), EnumInt(NightSceneGender.Female));
        let npcIsFemale = Equals(EnumInt(npcGender), EnumInt(NightSceneGender.Female));

        // GENDER-BASED TAG SELECTION DISABLED per user request: any gender may
        // use any animation now. Users can exclude specific animations via the
        // anim browser toggle instead. To restore gender-matched selection,
        // uncomment this block and remove the unconditional "paired" query below.
        // let eitherIsBig = Equals(EnumInt(playerGender), EnumInt(NightSceneGender.MaleBig)) || Equals(EnumInt(npcGender), EnumInt(NightSceneGender.MaleBig));
        // let tags: array<String>;
        // if playerIsFemale && npcIsFemale {
        //     ArrayPush(tags, "ff");
        // } else {
        //     if eitherIsBig {
        //         ArrayPush(tags, "mbf");
        //     } else {
        //         ArrayPush(tags, "mf");
        //     }
        // }
        // let emptyGenders: array<NightSceneGender>;
        // let animDef = registry.GetRandom(tags, 2, emptyGenders, false);
        // if !IsDefined(animDef) {
        //     if eitherIsBig {
        //         let mfTags: array<String>;
        //         ArrayPush(mfTags, "mf");
        //         animDef = registry.GetRandom(mfTags, 2, emptyGenders, false);
        //     }
        // }

        let emptyGenders: array<NightSceneGender>;
        let pairedTags: array<String>;
        ArrayPush(pairedTags, "paired");
        let animDef = registry.GetRandom(pairedTags, 2, emptyGenders, false);

        if !IsDefined(animDef) {
            LogChannel(n"NightScene", "No animations registered! Please install an animation pack.");
            return;
        }

        // Honor the player's position preference.
        let desiredPosition = manager.GetConfig().playerPosition;
        let actors = NightSceneDefeatHelper.OrderActorsForScene(player, npc, playerIsFemale, npcIsFemale, desiredPosition);

        // Use the midpoint between player and NPC as scene position
        let playerPos = player.GetWorldPosition();
        let npcPos = npc.GetWorldPosition();
        let scenePos = new Vector4(
            (playerPos.X + npcPos.X) / 2.0,
            (playerPos.Y + npcPos.Y) / 2.0,
            (playerPos.Z + npcPos.Z) / 2.0,
            1.0
        );

        LogChannel(n"NightScene", "Starting interaction with NPC");
        let started = manager.StartScene(animDef, actors, NightSceneTriggerSource.Interaction, scenePos);

        if started {
            // Signal the Lua side to spawn the workspot for this scene.
            NightSceneAPI.SetPendingWorkspotSpawn(true);
        }
    }
}
