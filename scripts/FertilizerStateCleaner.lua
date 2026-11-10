-- Admin console command "clearFertilizerState [fieldId]".
-- Clears only the Fertilizer value from the spray type ground layer of one field.
-- The density map is only ever modified on the server.

FertilizerStateCleaner = {}

---Returns the field containing the given world position, or nil.
function FertilizerStateCleaner.getFieldAtPosition(x, z)
    for _, field in pairs(g_fieldManager:getFields()) do
        local points = field.polygonPoints
        local inside = false
        local j = #points
        for i = 1, #points do
            local xi, _, zi = getWorldTranslation(points[i])
            local xj, _, zj = getWorldTranslation(points[j])
            if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then
                inside = not inside
            end
            j = i
        end
        if inside then
            return field
        end
    end

    return nil
end

---Server only. Sets the Fertilizer spray type to none on the given field.
-- @return boolean success
-- @return string message
function FertilizerStateCleaner.clearField(fieldId)
    local field = g_fieldManager:getFieldById(fieldId)
    if field == nil then
        return false, string.format("Invalid field id %s", tostring(fieldId))
    end

    local mapId, firstChannel, numChannels = g_currentMission.fieldGroundSystem:getDensityMapData(FieldDensityMap.SPRAY_TYPE)
    local fertilizerValue = FieldSprayType.getValueByType(FieldSprayType.FERTILIZER)

    local modifier = DensityMapModifier.new(mapId, firstChannel, numChannels, g_terrainNode)
    field.densityMapPolygon:applyToModifier(modifier)

    local filter = DensityMapFilter.new(mapId, firstChannel, numChannels)
    filter:setValueCompareParams(DensityValueCompareType.EQUAL, fertilizerValue)

    modifier:executeSet(0, filter)

    return true, string.format("Cleared fertilizer from field %d", fieldId)
end

---Server only. Sets the growth state of every crop on the given field.
-- Only cells that already hold a crop are changed, nothing is planted.
-- @return boolean success
-- @return string message
function FertilizerStateCleaner.setGrowthState(fieldId, state)
    local field = g_fieldManager:getFieldById(fieldId)
    if field == nil then
        return false, string.format("Invalid field id %s", tostring(fieldId))
    end

    -- only the dominant crop (largest area) is changed, other crops on the field are left alone
    local dominantDesc, dominantModifier, dominantFilter
    local dominantPixels = 0

    for _, desc in pairs(g_fruitTypeManager:getFruitTypes()) do
        if desc.terrainDataPlaneId == nil then
            continue
        end

        local modifier = DensityMapModifier.new(desc.terrainDataPlaneId, desc.startStateChannel, desc.numStateChannels, g_terrainNode)
        field.densityMapPolygon:applyToModifier(modifier)

        local filter = DensityMapFilter.new(modifier)
        filter:setValueCompareParams(DensityValueCompareType.GREATER, 0)

        local _, numPixels = modifier:executeGet(filter)
        if numPixels > dominantPixels then
            dominantDesc, dominantModifier, dominantFilter, dominantPixels = desc, modifier, filter, numPixels
        end
    end

    if dominantDesc == nil then
        return false, string.format("No crop on field %d", fieldId)
    end

    if state > dominantDesc.numFoliageStates then
        return false, string.format("Field %d: state %d out of range for %s (max %d)", fieldId, state, dominantDesc.name, dominantDesc.numFoliageStates)
    end

    if dominantDesc.terrainDataPlaneIdHaulm ~= nil then
        local haulmModifier = DensityMapModifier.new(dominantDesc.terrainDataPlaneIdHaulm, dominantDesc.startStateChannelHaulm, dominantDesc.numStateChannelsHaulm, g_terrainNode)
        field.densityMapPolygon:applyToModifier(haulmModifier)
        haulmModifier:executeSet(dominantDesc:getIsCut(state) and 1 or 0, dominantFilter)
    end

    dominantModifier:executeSet(state, dominantFilter)

    return true, string.format("Field %d: growth state %d set for %s", fieldId, state, dominantDesc.name)
end

---Returns the growth state distribution of the crops on the given field as text. Works on clients too.
function FertilizerStateCleaner.getGrowthStateInfo(fieldId)
    local field = g_fieldManager:getFieldById(fieldId)
    if field == nil then
        return string.format("Invalid field id %s", tostring(fieldId))
    end

    local lines = {}

    for _, desc in pairs(g_fruitTypeManager:getFruitTypes()) do
        if desc.terrainDataPlaneId == nil then
            continue
        end

        local modifier = DensityMapModifier.new(desc.terrainDataPlaneId, desc.startStateChannel, desc.numStateChannels, g_terrainNode)
        field.densityMapPolygon:applyToModifier(modifier)

        local filter = DensityMapFilter.new(modifier)
        filter:setValueCompareParams(DensityValueCompareType.GREATER, 0)

        local _, total = modifier:executeGet(filter)
        if total > 0 then
            local parts = {}
            for state = 1, desc.numFoliageStates do
                filter:setValueCompareParams(DensityValueCompareType.EQUAL, state)
                local _, numPixels = modifier:executeGet(filter)
                if numPixels > 0 then
                    table.insert(parts, string.format("%d (%s) %d%%", state, desc:getGrowthStateName(state) or "?", math.floor(100 * numPixels / total + 0.5)))
                end
            end
            table.insert(lines, string.format("%s: %s", desc.name, table.concat(parts, ", ")))
        end
    end

    if #lines == 0 then
        return string.format("Field %d: no crop", fieldId)
    end

    return string.format("Field %d: %s", fieldId, table.concat(lines, "; "))
end

---Resolves the field id from an optional console argument, falling back to the field under the player.
-- @return number|nil fieldId
-- @return string|nil error message
function FertilizerStateCleaner.resolveFieldId(fieldIdStr, usage)
    if fieldIdStr ~= nil then
        local fieldId = tonumber(fieldIdStr)
        if fieldId == nil or g_fieldManager:getFieldById(fieldId) == nil then
            return nil, "Invalid field id. Use: " .. usage
        end

        return fieldId
    end

    if g_localPlayer == nil then
        return nil, "No player position available, use: " .. usage
    end

    local x, _, z = g_localPlayer:getPosition()
    local field = FertilizerStateCleaner.getFieldAtPosition(x, z)
    if field == nil then
        return nil, "Not standing on a field, use: " .. usage
    end

    return field:getId()
end

---Client side convenience check, the server re-checks the sender.
function FertilizerStateCleaner.getIsAllowed()
    local mission = g_currentMission
    return mission:getIsServer() or mission.isMasterUser
end

function FertilizerStateCleaner.consoleCommandClear(_, fieldIdStr)
    if not FertilizerStateCleaner.getIsAllowed() then
        return "Command not allowed"
    end

    local usage = "clearFertilizerState [fieldId]"
    local fieldId, err = FertilizerStateCleaner.resolveFieldId(fieldIdStr, usage)
    if fieldId == nil then
        return err
    end

    if g_currentMission:getIsServer() then
        local _, message = FertilizerStateCleaner.clearField(fieldId)
        return message
    end

    g_client:getServerConnection():sendEvent(FertilizerStateCleanerEvent.new(fieldId, FertilizerStateCleanerEvent.ACTION_CLEAR))

    return string.format("Requested fertilizer clear for field %d", fieldId)
end

-- setGrowthState [fieldId] <state>: one argument is the state, two are fieldId and state.
function FertilizerStateCleaner.consoleCommandSetGrowthState(_, arg1, arg2)
    if not FertilizerStateCleaner.getIsAllowed() then
        return "Command not allowed"
    end

    local usage = "setGrowthState [fieldId] <state>"
    local fieldIdStr, stateStr = arg1, arg2
    if arg2 == nil then
        fieldIdStr, stateStr = nil, arg1
    end

    local state = tonumber(stateStr)
    if state == nil or state < 1 or state > 255 or state ~= math.floor(state) then
        return "Invalid growth state. Use: " .. usage
    end

    local fieldId, err = FertilizerStateCleaner.resolveFieldId(fieldIdStr, usage)
    if fieldId == nil then
        return err
    end

    if g_currentMission:getIsServer() then
        local _, message = FertilizerStateCleaner.setGrowthState(fieldId, state)
        return message
    end

    g_client:getServerConnection():sendEvent(FertilizerStateCleanerEvent.new(fieldId, FertilizerStateCleanerEvent.ACTION_SET_GROWTH, state))

    return string.format("Requested growth state %d for field %d", state, fieldId)
end

function FertilizerStateCleaner.consoleCommandGetGrowthState(_, fieldIdStr)
    local fieldId, err = FertilizerStateCleaner.resolveFieldId(fieldIdStr, "getGrowthState [fieldId]")
    if fieldId == nil then
        return err
    end

    return FertilizerStateCleaner.getGrowthStateInfo(fieldId)
end

addConsoleCommand("clearFertilizerState", "Clears the fertilizer layer from a field (admin only). Without argument uses the field under the player.", "consoleCommandClear", FertilizerStateCleaner, "[fieldId]")
addConsoleCommand("setGrowthState", "Sets the growth state of the crops on a field (admin only). With one argument uses the field under the player.", "consoleCommandSetGrowthState", FertilizerStateCleaner, "[fieldId]; <state>")
addConsoleCommand("getGrowthState", "Shows the growth states of the crops on a field. Without argument uses the field under the player.", "consoleCommandGetGrowthState", FertilizerStateCleaner, "[fieldId]")
