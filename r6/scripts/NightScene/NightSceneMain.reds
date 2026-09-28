// NightScene Framework - Main Entry Point
// ==========================================
// This is the bootstrap file for the NightScene framework.
// It initializes all subsystems when the game loads and
// registers example/test animations for development.
//
// LOAD ORDER: Redscript loads all .reds files in alphabetical order
//             within each directory. This file is in the root of
//             the NightScene folder, so core/ files load first.

// ============================================================
//  FRAMEWORK INITIALIZATION
// ============================================================

/// Hook into game session start to initialize the framework.
/// VERIFY: The exact lifecycle hook for session/game load.
///         PlayerPuppet.OnGameAttached or similar.
@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
    let result = wrappedMethod();

    // Initialize the framework (singletons are created on first access)
    NightSceneBootstrap.Initialize();

    return result;
}

/// Hook into game session end to clean up.
@wrapMethod(PlayerPuppet)
protected cb func OnDetach() -> Bool {
    NightSceneBootstrap.Shutdown();
    return wrappedMethod();
}

/// Bootstrap helper -- handles one-time initialization.
public abstract class NightSceneBootstrap {

    public static func Initialize() -> Void {
        if NightSceneServices.Get().IsInitialized() {
            return;
        }

        LogChannel(n"NightScene", "==============================================");
        LogChannel(n"NightScene", " NightScene Framework v0.1.0 - Initializing");
        LogChannel(n"NightScene", "==============================================");

        // Touch all singletons to ensure they're created
        let registry = NightSceneServices.Get().AnimRegistry();
        let manager = NightSceneServices.Get().SceneManager();
        let actorCtrl = NightSceneServices.Get().ActorController();
        let cameraCtrl = NightSceneServices.Get().CameraController();
        let eventBus = NightSceneServices.Get().EventBus();
        let interactionHandler = NightSceneServices.Get().InteractionHandler();

        // Animations are registered by the CET Lua loader (NightScene/init.lua)
        // which scans AMM collab pose packs on game load.

        // Start the health monitor for defeat detection
        NightSceneServices.Get().HealthMonitor().Start();

        LogChannel(n"NightScene", "Framework initialized. Waiting for CET loader to register animations.");
        LogChannel(n"NightScene", "==============================================");

        NightSceneServices.Get().SetInitialized(true);
    }

    public static func Shutdown() -> Void {
        if !NightSceneServices.Get().IsInitialized() {
            return;
        }

        // Cancel any active scene
        let manager = NightSceneServices.Get().SceneManager();
        if manager.IsSceneActive() {
            manager.CancelScene();
        }

        // Clear all singleton references so they are re-created on next session
        NightSceneServices.Get().ClearAll();

        LogChannel(n"NightScene", "NightScene Framework shut down");
    }

    /// Register placeholder test animations for development.
    /// In production, animation packs register themselves via the API.
    /// This demonstrates the registration pattern for pack developers.
    private static func RegisterTestAnimations() -> Void {
        let registry = NightSceneServices.Get().AnimRegistry();

        // ---- Test Animation 1: Simple standing 2-actor, 2-stage ----
        let stage1 = NightSceneStageBuilder.Create("Stage 1")
            .SetDuration(10.0)
            .SetSpeed(1.0)
            .SetTransition(NightSceneTransition.Instant)
            .AddActorAnim(
                n"ns_test_standing_s1_subject",    // REPLACE: with actual anim name from your .anims
                r"base\\animations\\nightscene\\test_standing.anims",  // REPLACE: with actual resource path
                NightSceneActorRole.Subject,
                10.0
            )
            .AddActorAnim(
                n"ns_test_standing_s1_partner",
                r"base\\animations\\nightscene\\test_standing.anims",
                NightSceneActorRole.Partner,
                10.0
            )
            .Build();

        let stage2 = NightSceneStageBuilder.Create("Stage 2")
            .SetDuration(15.0)
            .SetSpeed(1.0)
            .SetTransition(NightSceneTransition.CrossFade)
            .AddActorAnim(
                n"ns_test_standing_s2_subject",
                r"base\\animations\\nightscene\\test_standing.anims",
                NightSceneActorRole.Subject,
                15.0
            )
            .AddActorAnim(
                n"ns_test_standing_s2_partner",
                r"base\\animations\\nightscene\\test_standing.anims",
                NightSceneActorRole.Partner,
                15.0
            )
            .Build();

        let testAnim1 = NightSceneAnimBuilder.Create("nightscene_test_standing_01", "NightScene_BuiltIn")
            .SetDisplayName("Test Standing Animation 01")
            .SetActorCount(2)
            .AddGenderTag(NightSceneGender.Any)  // Subject can be any gender
            .AddGenderTag(NightSceneGender.Any)  // Partner can be any gender
            .AddTag("standing")
            .AddTag("interaction")
            .SetSupportsFirstPerson(true)
            .AddStage(stage1)
            .AddStage(stage2)
            .Build();

        registry.RegisterAnimation(testAnim1);

        // ---- Test Animation 2: Defeat scenario ----
        let defeatStage = NightSceneStageBuilder.Create("Defeat")
            .SetDuration(20.0)
            .SetSpeed(1.0)
            .AddActorAnim(
                n"ns_test_defeat_subject",
                r"base\\animations\\nightscene\\test_defeat.anims",
                NightSceneActorRole.Subject,
                20.0
            )
            .AddActorAnim(
                n"ns_test_defeat_partner",
                r"base\\animations\\nightscene\\test_defeat.anims",
                NightSceneActorRole.Partner,
                20.0
            )
            .Build();

        let testAnim2 = NightSceneAnimBuilder.Create("nightscene_test_defeat_01", "NightScene_BuiltIn")
            .SetDisplayName("Test Defeat Animation 01")
            .SetActorCount(2)
            .AddGenderTag(NightSceneGender.Female)  // Subject = female (Female V)
            .AddGenderTag(NightSceneGender.Male)    // Partner = male attacker
            .AddTag("defeat")
            .AddTag("lying")
            .SetSupportsFirstPerson(true)
            .AddStage(defeatStage)
            .Build();

        registry.RegisterAnimation(testAnim2);

        LogChannel(n"NightScene", "Registered " + IntToString(registry.GetCount()) + " test animations");
    }
}

// ============================================================
//  EXAMPLE: How an animation pack mod would register animations
// ============================================================
//
// An animation pack mod would create a separate .reds file that
// hooks into the framework initialization. Here's the pattern:
//
//   // File: r6/scripts/MyAnimPack/MyAnimPackInit.reds
//
//   @wrapMethod(PlayerPuppet)
//   protected cb func OnGameAttached() -> Bool {
//       let result = wrappedMethod();
//       MyAnimPack.RegisterAll();
//       return result;
//   }
//
//   public abstract class MyAnimPack {
//       public static func RegisterAll() -> Void {
//           let registry = NightSceneAnimRegistry.GetInstance();
//
//           // Build and register each animation...
//           let stage1 = NightSceneStageBuilder.Create("Kiss")
//               .SetDuration(8.0)
//               .AddActorAnim(n"mypack_kiss_female", r"mypack\\anims\\kiss.anims", NightSceneActorRole.Subject, 8.0)
//               .AddActorAnim(n"mypack_kiss_male", r"mypack\\anims\\kiss.anims", NightSceneActorRole.Partner, 8.0)
//               .Build();
//
//           let anim = NightSceneAnimBuilder.Create("mypack_kiss_01", "MyAnimPack")
//               .SetDisplayName("Romantic Kiss")
//               .SetActorCount(2)
//               .AddGenderTag(NightSceneGender.Female)
//               .AddGenderTag(NightSceneGender.Male)
//               .AddTag("kiss")
//               .AddTag("romantic")
//               .AddTag("standing")
//               .AddTag("interaction")
//               .SetSupportsFirstPerson(true)
//               .AddStage(stage1)
//               .Build();
//
//           registry.RegisterAnimation(anim);
//       }
//   }
