// NightScene Framework - Camera Controller
// ===========================================
// Manages camera overrides during scenes:
//   - First-person bone attachment (key differentiator from existing mods)
//   - Third-person orbit camera
//   - Cinematic preset angles
//   - Free camera for player control
//
// VERIFY: Camera system hooks need verification against decompiled scripts.
//         The camera system in CP2077 uses FPPCameraComponent and TPPCameraComponent.

/// Stored camera state for restoration after a scene.
public class NightSceneSavedCameraState extends IScriptable {
    public let wasFirstPerson: Bool;
    public let fov: Float;
    public let cameraPosition: Vector4;
    public let cameraOrientation: Quaternion;
}

/// Cinematic camera preset definition.
public class NightSceneCameraPreset extends IScriptable {
    public let name: String;
    public let positionOffset: Vector4;      // Offset from scene center
    public let lookAtOffset: Vector4;        // Where to look relative to scene center
    public let fov: Float;                   // Field of view
    public let attachToBone: CName;          // If set, camera follows this bone
    public let attachToActorIndex: Int32;    // Which actor to attach to (-1 = scene root)
}

/// Singleton camera controller for NightScene.
public class NightSceneCameraController extends IScriptable {

    // Saved pre-scene camera state
    private let m_savedState: ref<NightSceneSavedCameraState>;

    // Whether we've overridden the camera
    private let m_isOverriding: Bool;

    // Current camera mode
    private let m_currentMode: NightSceneCameraMode;

    // Available cinematic presets
    private let m_presets: array<ref<NightSceneCameraPreset>>;

    // Current cinematic preset index
    private let m_currentPresetIndex: Int32;

    /// Set up default cinematic camera presets.
    public func InitializePresets() -> Void {
        this.m_isOverriding = false;
        this.m_currentPresetIndex = 0;

        // Preset 1: Front medium shot
        let front = new NightSceneCameraPreset();
        front.name = "Front Medium";
        front.positionOffset = new Vector4(0.0, -2.0, 1.5, 0.0);
        front.lookAtOffset = new Vector4(0.0, 0.0, 1.0, 0.0);
        front.fov = 60.0;
        front.attachToActorIndex = -1;
        ArrayPush(this.m_presets, front);

        // Preset 2: Side shot
        let side = new NightSceneCameraPreset();
        side.name = "Side";
        side.positionOffset = new Vector4(2.0, 0.0, 1.2, 0.0);
        side.lookAtOffset = new Vector4(0.0, 0.0, 1.0, 0.0);
        side.fov = 55.0;
        side.attachToActorIndex = -1;
        ArrayPush(this.m_presets, side);

        // Preset 3: Close-up (attached to actor head bone)
        let closeup = new NightSceneCameraPreset();
        closeup.name = "Close-Up";
        closeup.positionOffset = new Vector4(0.0, -0.8, 0.1, 0.0);
        closeup.lookAtOffset = new Vector4(0.0, 0.0, 0.0, 0.0);
        closeup.fov = 45.0;
        closeup.attachToBone = n"Head";
        closeup.attachToActorIndex = 1; // Partner
        ArrayPush(this.m_presets, closeup);

        // Preset 4: Top-down
        let topdown = new NightSceneCameraPreset();
        topdown.name = "Top Down";
        topdown.positionOffset = new Vector4(0.0, 0.0, 3.5, 0.0);
        topdown.lookAtOffset = new Vector4(0.0, 0.0, 0.5, 0.0);
        topdown.fov = 70.0;
        topdown.attachToActorIndex = -1;
        ArrayPush(this.m_presets, topdown);

        LogChannel(n"NightScene", "Camera presets initialized: " + IntToString(ArraySize(this.m_presets)));
    }

    // -------------------------------------------------------
    //  CAMERA APPLICATION
    // -------------------------------------------------------

    /// Apply the appropriate camera for the current scene state.
    public func ApplySceneCamera(scene: ref<NightSceneInstance>) -> Void {
        if !IsDefined(scene) {
            return;
        }

        // Save current camera state if we haven't already
        if !this.m_isOverriding {
            this.SaveCameraState(scene);
            this.m_isOverriding = true;
        }

        this.m_currentMode = scene.cameraMode;

        let cameraMode = scene.cameraMode;

        if Equals(EnumInt(cameraMode), EnumInt(NightSceneCameraMode.FirstPerson)) {
            this.ApplyFirstPerson(scene);
        } else {
            if Equals(EnumInt(cameraMode), EnumInt(NightSceneCameraMode.ThirdPerson)) {
                this.ApplyThirdPerson(scene);
            } else {
                if Equals(EnumInt(cameraMode), EnumInt(NightSceneCameraMode.Cinematic)) {
                    this.ApplyCinematic(scene);
                } else {
                    this.ApplyFreeCamera(scene);
                }
            }
        }
    }

    /// Save the current camera state before overriding.
    private func SaveCameraState(scene: ref<NightSceneInstance>) -> Void {
        this.m_savedState = new NightSceneSavedCameraState();

        // Read current camera state from the player's FPP camera component
        let playerActor = this.FindPlayerActor(scene);
        if IsDefined(playerActor) {
            let player = playerActor.entity as PlayerPuppet;
            if IsDefined(player) {
                let fppCam = player.GetFPPCameraComponent();
                if IsDefined(fppCam) {
                    this.m_savedState.fov = fppCam.GetFOV();
                    this.m_savedState.wasFirstPerson = true;
                } else {
                    this.m_savedState.fov = 70.0;
                    this.m_savedState.wasFirstPerson = true;
                }
            }
        }
        LogChannel(n"NightScene", "Saved camera state (FOV: " + FloatToString(this.m_savedState.fov) + ")");
    }

    /// Helper: find the player actor in a scene.
    private func FindPlayerActor(scene: ref<NightSceneInstance>) -> ref<NightSceneActorState> {
        let i: Int32 = 0;
        while i < ArraySize(scene.actors) {
            if scene.actors[i].isPlayer {
                return scene.actors[i];
            }
            i += 1;
        }
        return null;
    }

    // -------------------------------------------------------
    //  CAMERA MODES
    // -------------------------------------------------------

    /// First-person: Keep the FPP camera active on the player's head.
    /// During animations the skeleton drives the head bone, so the FPP camera
    /// naturally follows the animation. We adjust FOV for a tighter perspective.
    private func ApplyFirstPerson(scene: ref<NightSceneInstance>) -> Void {
        let playerActor = this.FindPlayerActor(scene);
        if !IsDefined(playerActor) {
            LogChannel(n"NightScene", "WARN: No player actor found for first-person camera");
            return;
        }

        let player = playerActor.entity as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }

        // Access the FPP camera component and adjust for scene viewing
        let fppCam = player.GetFPPCameraComponent();
        if IsDefined(fppCam) {
            // Ensure FPP camera is active
            fppCam.Activate(0.3);
            // Slightly narrower FOV for intimate perspective
            fppCam.SetFOV(60.0);
        }

        LogChannel(n"NightScene", "Applied first-person camera (FOV: 60)");
    }

    /// Third-person: Reposition the FPP camera behind/above the scene
    /// using local position offset to simulate a third-person view.
    private func ApplyThirdPerson(scene: ref<NightSceneInstance>) -> Void {
        let playerActor = this.FindPlayerActor(scene);
        if !IsDefined(playerActor) {
            return;
        }

        let player = playerActor.entity as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }

        let fppCam = player.GetFPPCameraComponent();
        if IsDefined(fppCam) {
            fppCam.Activate(0.3);
            // Pull camera back and up for a third-person perspective
            fppCam.SetLocalPosition(new Vector4(0.0, -2.5, 0.8, 1.0));
            fppCam.SetFOV(65.0);
        }

        LogChannel(n"NightScene", "Applied third-person camera");
    }

    /// Cinematic: Use the current preset camera angle by offsetting the FPP camera.
    private func ApplyCinematic(scene: ref<NightSceneInstance>) -> Void {
        if ArraySize(this.m_presets) == 0 {
            this.ApplyThirdPerson(scene);
            return;
        }

        let playerActor = this.FindPlayerActor(scene);
        if !IsDefined(playerActor) {
            return;
        }

        let player = playerActor.entity as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }

        let preset = this.m_presets[this.m_currentPresetIndex];

        let fppCam = player.GetFPPCameraComponent();
        if IsDefined(fppCam) {
            fppCam.Activate(0.5);
            // Apply preset offsets relative to the player
            fppCam.SetLocalPosition(preset.positionOffset);
            fppCam.SetFOV(preset.fov);
        }

        LogChannel(n"NightScene", "Cinematic camera: " + preset.name);
    }

    /// Free camera: Detach camera constraints so the player can look around freely.
    /// Uses a wide FOV and neutral position -- player uses mouse to look.
    private func ApplyFreeCamera(scene: ref<NightSceneInstance>) -> Void {
        let playerActor = this.FindPlayerActor(scene);
        if !IsDefined(playerActor) {
            return;
        }

        let player = playerActor.entity as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }

        let fppCam = player.GetFPPCameraComponent();
        if IsDefined(fppCam) {
            fppCam.Activate(0.3);
            // Pull back slightly and use wide FOV for free look
            fppCam.SetLocalPosition(new Vector4(0.0, -1.0, 0.5, 1.0));
            fppCam.SetFOV(75.0);
        }

        LogChannel(n"NightScene", "Applied free camera mode");
    }

    // -------------------------------------------------------
    //  PRESET CYCLING
    // -------------------------------------------------------

    /// Cycle to the next cinematic preset.
    public func NextPreset() -> Void {
        if ArraySize(this.m_presets) == 0 {
            return;
        }
        this.m_currentPresetIndex = (this.m_currentPresetIndex + 1) % ArraySize(this.m_presets);
        LogChannel(n"NightScene", "Camera preset: " + this.m_presets[this.m_currentPresetIndex].name);
    }

    /// Cycle to the previous cinematic preset.
    public func PreviousPreset() -> Void {
        if ArraySize(this.m_presets) == 0 {
            return;
        }
        this.m_currentPresetIndex -= 1;
        if this.m_currentPresetIndex < 0 {
            this.m_currentPresetIndex = ArraySize(this.m_presets) - 1;
        }
        LogChannel(n"NightScene", "Camera preset: " + this.m_presets[this.m_currentPresetIndex].name);
    }

    /// Add a custom camera preset (for mod extensibility).
    public func AddPreset(preset: ref<NightSceneCameraPreset>) -> Void {
        ArrayPush(this.m_presets, preset);
    }

    /// Get all available preset names (for UI display).
    public func GetPresetNames() -> array<String> {
        let names: array<String>;
        let i: Int32 = 0;
        while i < ArraySize(this.m_presets) {
            ArrayPush(names, this.m_presets[i].name);
            i += 1;
        }
        return names;
    }

    // -------------------------------------------------------
    //  RESTORATION
    // -------------------------------------------------------

    /// Restore the camera to its pre-scene state.
    public func RestoreCamera() -> Void {
        if !this.m_isOverriding {
            return;
        }

        // Restore camera by resetting FPP component to defaults
        let gi = GetGameInstance();
        let player = GetPlayer(gi);

        if IsDefined(player) {
            let fppCam = player.GetFPPCameraComponent();
            if IsDefined(fppCam) {
                // Reset local position offset to zero (default head position)
                fppCam.SetLocalPosition(new Vector4(0.0, 0.0, 0.0, 1.0));

                // Restore saved FOV
                if IsDefined(this.m_savedState) {
                    fppCam.SetFOV(this.m_savedState.fov);
                } else {
                    fppCam.SetFOV(70.0);
                }

                // Re-activate FPP camera to ensure it's the active camera
                fppCam.Activate(0.5);
            }
        }

        this.m_isOverriding = false;
        this.m_savedState = null;
        LogChannel(n"NightScene", "Camera restored");
    }
}
