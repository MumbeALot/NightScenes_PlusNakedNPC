// NakedNPC - Equipment System Bridge
// =====================================
// Adds public methods to EquipmentSystemPlayerData so NakedNPCSystem
// can call the private UnequipItem for real equipment removal.
// Clone V inherits the player's EQUIPMENT DATA, so we must use the
// real unequip path (same as manual inventory unequip).
//
// Verified signatures from NativeDB:
//   UnequipItem(equipAreaIndex: Int32, slotIndex: Int32, opt forceRemove: Bool) -> Void
//   EquipItem(itemID: ItemID, opt blockActiveSlotsUpdate: Bool, opt forceEquipWeapon: Bool) -> Void
//   GetEquipAreaIndex(areaType: gamedataEquipmentArea) -> Int32
//   GetItemInEquipSlot(equipAreaIndex: Int32, slotIndex: Int32) -> ItemID

/// Unequip a specific equipment area — both data AND visuals.
@addMethod(EquipmentSystemPlayerData)
public func NakedNPC_UnequipArea(areaIndex: Int32, area: gamedataEquipmentArea) -> Void {
    // Remove from equipment data (same as manual inventory unequip)
    this.UnequipItem(areaIndex, 0);
    // Also remove the visual mesh (forces the renderer to hide clothing)
    this.UnequipVisuals(area);
}

/// Re-equip all items that are still in their equipment area slots.
/// After UnequipItem, items stay in the area data but are visually removed.
/// This re-equips them by calling EquipItem for each valid item.
@addMethod(EquipmentSystemPlayerData)
public func NakedNPC_ReequipAll() -> Void {
    let i: Int32 = 0;
    let count: Int32 = 0;
    while i < ArraySize(this.m_equipment.equipAreas) {
        if ArraySize(this.m_equipment.equipAreas[i].equipSlots) > 0 {
            let itemID = this.m_equipment.equipAreas[i].equipSlots[0].itemID;
            if ItemID.IsValid(itemID) {
                this.EquipItem(itemID);
                count += 1;
            }
        }
        i += 1;
    }
    LogChannel(n"NakedNPC", "Re-equipped " + IntToString(count) + " items");
}
