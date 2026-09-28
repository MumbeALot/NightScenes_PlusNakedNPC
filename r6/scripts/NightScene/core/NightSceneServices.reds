// NightScene Framework - Service Locator
// ========================================
// Uses ScriptableSystem (same pattern as Dark Future) for singleton storage.
// The game engine manages the lifecycle. Access via NightSceneServices.Get().

public class NightSceneServices extends ScriptableSystem {
    private let m_actorController: ref<NightSceneActorController>;
    private let m_animRegistry: ref<NightSceneAnimRegistry>;
    private let m_cameraController: ref<NightSceneCameraController>;
    private let m_eventBus: ref<NightSceneEventBus>;
    private let m_sceneManager: ref<NightSceneManager>;
    private let m_interactionHandler: ref<NightSceneInteractionHandler>;
    private let m_healthMonitor: ref<NightSceneHealthMonitor>;
    private let m_initialized: Bool;

    // -- Access the singleton via the game's ScriptableSystem container --

    public final static func GetInstance(gi: GameInstance) -> ref<NightSceneServices> {
        let instance = GameInstance.GetScriptableSystemsContainer(gi).Get(n"NightSceneServices") as NightSceneServices;
        return instance;
    }

    public final static func Get() -> ref<NightSceneServices> {
        return NightSceneServices.GetInstance(GetGameInstance());
    }

    // -- Lifecycle --

    private func OnAttach() -> Void {
        LogChannel(n"NightScene", "NightSceneServices ScriptableSystem attached");
    }

    private func OnDetach() -> Void {
        LogChannel(n"NightScene", "NightSceneServices ScriptableSystem detached");
        this.m_actorController = null;
        this.m_animRegistry = null;
        this.m_cameraController = null;
        this.m_eventBus = null;
        this.m_sceneManager = null;
        this.m_interactionHandler = null;
        this.m_initialized = false;
    }

    // -- Lazy getters for each subsystem --

    public func ActorController() -> ref<NightSceneActorController> {
        if !IsDefined(this.m_actorController) {
            this.m_actorController = new NightSceneActorController();
        }
        return this.m_actorController;
    }

    public func AnimRegistry() -> ref<NightSceneAnimRegistry> {
        if !IsDefined(this.m_animRegistry) {
            this.m_animRegistry = new NightSceneAnimRegistry();
            this.m_animRegistry.Init();
        }
        return this.m_animRegistry;
    }

    public func CameraController() -> ref<NightSceneCameraController> {
        if !IsDefined(this.m_cameraController) {
            this.m_cameraController = new NightSceneCameraController();
            this.m_cameraController.InitializePresets();
        }
        return this.m_cameraController;
    }

    public func EventBus() -> ref<NightSceneEventBus> {
        if !IsDefined(this.m_eventBus) {
            this.m_eventBus = new NightSceneEventBus();
        }
        return this.m_eventBus;
    }

    public func SceneManager() -> ref<NightSceneManager> {
        if !IsDefined(this.m_sceneManager) {
            this.m_sceneManager = new NightSceneManager();
            this.m_sceneManager.Initialize();
        }
        return this.m_sceneManager;
    }

    public func InteractionHandler() -> ref<NightSceneInteractionHandler> {
        if !IsDefined(this.m_interactionHandler) {
            this.m_interactionHandler = new NightSceneInteractionHandler();
        }
        return this.m_interactionHandler;
    }

    public func HealthMonitor() -> ref<NightSceneHealthMonitor> {
        if !IsDefined(this.m_healthMonitor) {
            this.m_healthMonitor = new NightSceneHealthMonitor();
        }
        return this.m_healthMonitor;
    }

    public func IsInitialized() -> Bool {
        return this.m_initialized;
    }

    public func SetInitialized(value: Bool) -> Void {
        this.m_initialized = value;
    }

    public func ClearAll() -> Void {
        this.m_actorController = null;
        this.m_animRegistry = null;
        this.m_cameraController = null;
        this.m_eventBus = null;
        this.m_sceneManager = null;
        this.m_interactionHandler = null;
        if IsDefined(this.m_healthMonitor) {
            this.m_healthMonitor.Stop();
        }
        this.m_healthMonitor = null;
        this.m_initialized = false;
    }
}
