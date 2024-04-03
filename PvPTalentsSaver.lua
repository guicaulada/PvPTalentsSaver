function GetSelectedLoadoutConfigID()
  local lastSelected = PlayerUtil.GetCurrentSpecID() and
      C_ClassTalents.GetLastSelectedSavedConfigID(PlayerUtil.GetCurrentSpecID())
  local selectionID = ClassTalentFrame and ClassTalentFrame.TalentsTab and ClassTalentFrame.TalentsTab.LoadoutDropDown and
      ClassTalentFrame.TalentsTab.LoadoutDropDown.GetSelectionID and
      ClassTalentFrame.TalentsTab.LoadoutDropDown:GetSelectionID()

  -- the priority in authoritativeness is [default UI's dropdown] > [API] > ['ActiveConfigID'] > nil
  -- nil happens when you don't have any spec selected, e.g. on a freshly created character
  return selectionID or lastSelected or C_ClassTalents.GetActiveConfigID() or nil
end

local f = CreateFrame("Frame")

function f:OnEvent(event, ...)
  self[event](self, event, ...)
end

function f:ADDON_LOADED(_, addOnName)
  if addOnName == "PvPTalentsSaver" then
    PvPTalentsSaverDB = PvPTalentsSaverDB or {}
    self.db = PvPTalentsSaverDB
  end
end

function f:TRAIT_TREE_CURRENCY_INFO_UPDATED()
  configID = GetSelectedLoadoutConfigID()
  if configID then
    if self.db[configID] == nil then
      self.db[configID] = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()
    end
    for index, talentID in ipairs(self.db[configID]) do
      LearnPvpTalent(talentID, index)
    end
  end
end

function f:PLAYER_PVP_TALENT_UPDATE()
  configID = GetSelectedLoadoutConfigID()
  if configID then
    self.db[configID] = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()
  end
end

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_PVP_TALENT_UPDATE")
f:RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED")

f:SetScript("OnEvent", f.OnEvent)
