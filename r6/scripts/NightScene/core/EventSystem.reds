// NightScene Framework - Event System
// =====================================
// Provides a pub/sub event dispatcher so other mods can react to
// scene lifecycle events.  Modeled after Codeware's CallbackSystem
// but specific to NightScene events.
//
// Usage from another mod:
//   NightSceneEventBus.GetInstance().Subscribe(n"OnSceneStart", myCallback);

/// Callback interface that listeners must implement.
public abstract class NightSceneCallback extends IScriptable {
    public func OnNightSceneEvent(eventName: CName, data: ref<NightSceneEventData>) -> Void;
}

/// Wrapper that stores a callback reference with its subscribed event.
public class NightSceneSubscription extends IScriptable {
    public let eventName: CName;
    public let callback: wref<NightSceneCallback>;
}

/// Singleton event bus for the NightScene framework.
/// All scene lifecycle events are dispatched through here.
public class NightSceneEventBus extends IScriptable {
    private let m_subscriptions: array<ref<NightSceneSubscription>>;
    /// Subscribe to a named event.
    /// Known event names:
    ///   n"OnSceneStart"       -- scene begins (state -> Playing)
    ///   n"OnStageChange"      -- stage advances
    ///   n"OnSceneEnd"         -- scene finishes or is cancelled
    ///   n"OnSceneError"       -- an error occurred
    ///   n"OnDefeatTriggered"  -- combat defeat detected
    ///   n"OnActorReady"       -- an actor has been positioned & prepped
    public func Subscribe(eventName: CName, callback: ref<NightSceneCallback>) -> Void {
        let sub = new NightSceneSubscription();
        sub.eventName = eventName;
        sub.callback = callback;
        ArrayPush(this.m_subscriptions, sub);
    }

    /// Unsubscribe a specific callback from a specific event.
    public func Unsubscribe(eventName: CName, callback: ref<NightSceneCallback>) -> Void {
        let i: Int32 = ArraySize(this.m_subscriptions) - 1;
        while i >= 0 {
            let sub = this.m_subscriptions[i];
            if Equals(sub.eventName, eventName) && IsDefined(sub.callback) {
                // Compare by reference identity
                if Equals(sub.callback, callback) {
                    ArrayErase(this.m_subscriptions, i);
                }
            }
            i -= 1;
        }
    }

    /// Unsubscribe all callbacks for a given listener object.
    public func UnsubscribeAll(callback: ref<NightSceneCallback>) -> Void {
        let i: Int32 = ArraySize(this.m_subscriptions) - 1;
        while i >= 0 {
            if Equals(this.m_subscriptions[i].callback, callback) {
                ArrayErase(this.m_subscriptions, i);
            }
            i -= 1;
        }
    }

    /// Dispatch an event to all subscribers of the given event name.
    public func Dispatch(eventName: CName, data: ref<NightSceneEventData>) -> Void {
        let i: Int32 = 0;
        while i < ArraySize(this.m_subscriptions) {
            let sub = this.m_subscriptions[i];
            if Equals(sub.eventName, eventName) && IsDefined(sub.callback) {
                sub.callback.OnNightSceneEvent(eventName, data);
            }
            i += 1;
        }
        // Clean up dead references (callbacks that were garbage collected)
        this.PruneDeadSubscriptions();
    }

    /// Remove subscriptions whose callback reference has been collected.
    private func PruneDeadSubscriptions() -> Void {
        let i: Int32 = ArraySize(this.m_subscriptions) - 1;
        while i >= 0 {
            if !IsDefined(this.m_subscriptions[i].callback) {
                ArrayErase(this.m_subscriptions, i);
            }
            i -= 1;
        }
    }

    /// Helper: Build and dispatch a standard event data packet.
    public func DispatchSceneEvent(eventName: CName, scene: ref<NightSceneInstance>) -> Void {
        let data = new NightSceneEventData();
        data.sceneId = scene.sceneId;
        data.state = scene.state;
        data.stageIndex = scene.currentStageIndex;
        data.triggerSource = scene.triggerSource;
        data.animId = scene.animDef.id;
        this.Dispatch(eventName, data);
    }
}
