-- Rewritten with Gemini: https://g.co/gemini/share/8efe15f94476
-- Saves and loads PvP talent configurations automatically when WoW's built-in talent loadouts are swapped.
-- This addon links PvP talent sets directly to the game's default talent loadouts.

-- Create a local frame to handle events. This is a common WoW addon practice.
local frame = CreateFrame("Frame")

-- This table will store the mapping between talent loadout IDs and their associated PvP talent sets.
-- It's declared globally (without 'local') so WoW saves it per character in SavedVariables.
-- The .toc file must declare "## SavedVariables: PvPTalentsSaverDB" for this to work.
PvPTalentsSaverDB = PvPTalentsSaverDB or {}

-- Stores the ID of the last known active talent loadout. Used to detect changes.
-- This is a session-only variable, stored on the event frame itself.
frame.lastKnownLoadoutID = nil

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

-- GetCurrentSelectedLoadoutID
-- Retrieves the ConfigID of the currently selected talent loadout for the player's active specialization.
-- Returns: number (loadoutID) or nil if not available.
local function GetCurrentSelectedLoadoutID()
    -- PlayerUtil.GetCurrentSpecID() returns the player's current specialization ID.
    local currentSpecID = PlayerUtil.GetCurrentSpecID()
    if not currentSpecID then
        -- This can happen very early during game load before spec information is available.
        return nil
    end
    -- C_ClassTalents.GetLastSelectedSavedConfigID(specID) returns the ID of the
    -- talent loadout that the player has currently selected within that specialization.
    -- This is the key ID we use to associate PvP talents with a specific game loadout.
    return C_ClassTalents.GetLastSelectedSavedConfigID(currentSpecID)
end

--------------------------------------------------------------------------------
-- Core Logic: Applying and Saving PvP Talents
--------------------------------------------------------------------------------

-- ApplyPvpTalents
-- Applies the saved PvP talents for the given loadoutID.
-- loadoutID: The ConfigID of the talent loadout to apply PvP talents for.
local function ApplyPvpTalents(loadoutID)
    if not loadoutID then return end -- Safety check

    -- Check if we have any PvP talents saved for this specific loadout ID.
    if PvPTalentsSaverDB[loadoutID] then
        local savedTalents = PvPTalentsSaverDB[loadoutID] -- Array of PvP talent IDs, e.g., {id1, id2, id3}
        -- C_SpecializationInfo.GetAllSelectedPvpTalentIDs() returns an array of currently learned PvP talent IDs.
        local currentPvpTalents = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()

        -- Assume a maximum of 3 PvP talent slots, common for max-level characters.
        -- The game's UI and systems typically handle characters with fewer available slots correctly.
        local MAX_PVP_SLOTS = 3
        
        local needsChange = false
        local talentsToLearn = {} -- Store talents that need to be learned in {slotIndex = talentID} format

        -- Compare saved talents with current talents for each slot.
        for i = 1, MAX_PVP_SLOTS do
            local savedTalentID_for_slot = savedTalents[i] or 0       -- Talent ID from our DB for this slot (0 if none/unmanaged).
            local currentTalentID_for_slot = currentPvpTalents[i] or 0 -- Current live talent in this slot.

            -- We only intervene if our saved data specifies a particular talent for this slot (savedTalentID_for_slot ~= 0).
            -- And if that saved talent is different from what's currently active in that slot.
            if savedTalentID_for_slot ~= 0 and savedTalentID_for_slot ~= currentTalentID_for_slot then
                -- GetPvpTalentInfoByID (global function) checks if a talent ID is valid.
                if GetPvpTalentInfoByID(savedTalentID_for_slot) then
                    talentsToLearn[i] = savedTalentID_for_slot
                    needsChange = true
                end
            end
        end

        if needsChange then
            -- Learn the necessary talents. The game handles unlearning the previous talent in a slot
            -- when a new one is learned for that same slot.
            for slotIndex = 1, MAX_PVP_SLOTS do
                if talentsToLearn[slotIndex] then
                    -- LearnPvpTalent (global function) applies the talent to the specified slot.
                    LearnPvpTalent(talentsToLearn[slotIndex], slotIndex)
                end
            end
        end
    end
end

-- SavePvpTalents
-- Saves the currently selected PvP talents to the PvPTalentsSaverDB for the given loadoutID.
-- loadoutID: The ConfigID of the talent loadout to save PvP talents for.
local function SavePvpTalents(loadoutID)
    if not loadoutID then return end -- Safety check

    -- Get all currently selected PvP talent IDs.
    local currentPvpTalents = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()
    -- Store this array in our database, keyed by the loadout ID.
    PvPTalentsSaverDB[loadoutID] = currentPvpTalents
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

frame:SetScript("OnEvent", function(self, event, ...)
    local args = {...} -- Capture varargs for event payloads.

    if event == "ADDON_LOADED" then
        if args[1] == "PvPTalentsSaver" then -- Check if it's our addon loading.
            -- Initialize lastKnownLoadoutID after a very brief delay.
            -- APIs might not be ready immediately on ADDON_LOADED.
            C_Timer.After(0.1, function() 
                self.lastKnownLoadoutID = GetCurrentSelectedLoadoutID() 
            end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- This event fires when the player enters the world (login, zoning, reload UI).
        -- isInitialLogin = args[1], isReloadingUi = args[2]
        -- This is a good point to perform initial talent synchronization.
        C_Timer.After(0.2, function() -- Delay to allow game systems to fully initialize.
            local initialLoadoutID = GetCurrentSelectedLoadoutID()
            if initialLoadoutID then
                ApplyPvpTalents(initialLoadoutID)
                self.lastKnownLoadoutID = initialLoadoutID
            end
        end)
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- This event fires when the player's active specialization changes.
        -- args[1] (newSpecGroupIndex): The index of the new specialization group (1-based).
        -- args[2] (oldSpecGroupIndex): The index of the previous specialization group.
        -- A value of 0 for oldSpecGroupIndex typically indicates initial spec selection (e.g., on login).
        
        -- Defer processing to the next frame. This helps ensure that
        -- GetCurrentSelectedLoadoutID() returns the ID for the *new* spec/loadout state.
        C_Timer.After(0, function()
            local newSelectedLoadoutID = GetCurrentSelectedLoadoutID()
            if args[1] ~= args[2] then -- Indicates an actual change in specialization.
                if newSelectedLoadoutID then
                    ApplyPvpTalents(newSelectedLoadoutID)
                    self.lastKnownLoadoutID = newSelectedLoadoutID
                end
            else 
                -- If newSpecGroupIndex == oldSpecGroupIndex (e.g., event fired as "1,1"),
                -- it means the spec itself didn't change. This can sometimes happen
                -- as a side effect of other talent/PvP talent operations (like LearnPvpTalent).
                -- In this case, we usually don't need to re-apply talents based on this event,
                -- as TRAIT_CONFIG_UPDATED handles intra-spec loadout changes.
                -- We still update lastKnownLoadoutID if a valid one is found for consistency.
                if newSelectedLoadoutID then self.lastKnownLoadoutID = newSelectedLoadoutID end
            end
        end)
    elseif event == "TRAIT_CONFIG_UPDATED" then
        -- This event fires when the "active config" for the current specialization is updated.
        -- This includes activating a different talent loadout within the same spec.
        -- args[1] (active_config_id): The ID of the spec's active config (not the loadout ID directly).
        
        -- Defer processing to the next frame. This is CRUCIAL because
        -- C_ClassTalents.GetLastSelectedSavedConfigID() might still return the *old*
        -- loadout ID if called immediately within this event handler. The delay allows
        -- the API to update its state.
        C_Timer.After(0, function() 
            local newlySelectedLoadoutID = GetCurrentSelectedLoadoutID()
            if newlySelectedLoadoutID then
                if self.lastKnownLoadoutID ~= newlySelectedLoadoutID then
                    -- A different loadout has been selected.
                    ApplyPvpTalents(newlySelectedLoadoutID)
                    self.lastKnownLoadoutID = newlySelectedLoadoutID
                end
            end
        end)
    elseif event == "PLAYER_PVP_TALENT_UPDATE" then
        -- This event fires whenever a PvP talent is learned or unlearned,
        -- either by direct player interaction or by an addon calling LearnPvpTalent.
        -- We save the current set of PvP talents to the active loadout.
        -- No timer is needed here; we want to capture the state immediately as the game reports it.
        local currentLoadoutID = GetCurrentSelectedLoadoutID()
        if currentLoadoutID then
            SavePvpTalents(currentLoadoutID)
            self.lastKnownLoadoutID = currentLoadoutID -- Keep lastKnownLoadoutID synced.
        end
    end
end)

--------------------------------------------------------------------------------
-- Event Registration
--------------------------------------------------------------------------------

-- Register for events needed by the addon.
frame:RegisterEvent("ADDON_LOADED")           -- To initialize when this addon is loaded.
frame:RegisterEvent("PLAYER_ENTERING_WORLD")  -- For initial talent sync when player enters the game.
frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED") -- When player changes class specialization.
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")   -- When player changes talent loadouts within a spec.
frame:RegisterEvent("PLAYER_PVP_TALENT_UPDATE") -- When player changes a PvP talent.
