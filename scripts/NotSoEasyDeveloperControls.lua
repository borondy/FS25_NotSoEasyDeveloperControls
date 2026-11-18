-- Admin console command "nseClearFertilizerState [fieldId]".
-- Clears only the Fertilizer value from the spray type ground layer of one field.
-- The density map is only ever modified on the server.

NotSoEasyDeveloperControls = {}

---Returns the field containing the given world position, or nil.
function NotSoEasyDeveloperControls.getFieldAtPosition(x, z)
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
function NotSoEasyDeveloperControls.clearField(fieldId)
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
function NotSoEasyDeveloperControls.setGrowthState(fieldId, state)
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

---Server only. Sets the ground type of the whole given field.
-- groundTypeId is the FieldGroundType enum id (1 = NONE ... 16 = GRASS_CUT).
-- @return boolean success
-- @return string message
function NotSoEasyDeveloperControls.setGroundType(fieldId, groundTypeId)
    local field = g_fieldManager:getFieldById(fieldId)
    if field == nil then
        return false, string.format("Invalid field id %s", tostring(fieldId))
    end

    local groundTypeName = FieldGroundType.getName(groundTypeId)
    local value = groundTypeName ~= nil and FieldGroundType.getValueByType(groundTypeId) or nil
    if value == nil then
        return false, string.format("Invalid ground type id %s. %s", tostring(groundTypeId), NotSoEasyDeveloperControls.getGroundTypeList())
    end

    local mapId, firstChannel, numChannels = g_currentMission.fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)

    local modifier = DensityMapModifier.new(mapId, firstChannel, numChannels, g_terrainNode)
    field.densityMapPolygon:applyToModifier(modifier)
    modifier:executeSet(value)

    return true, string.format("Field %d: ground type set to %d (%s)", fieldId, groundTypeId, groundTypeName)
end

---Returns the valid ground type ids as text.
function NotSoEasyDeveloperControls.getGroundTypeList()
    local parts = {}
    for id = 1, 64 do
        local name = FieldGroundType.getName(id)
        if name == nil then
            break
        end
        table.insert(parts, string.format("%d=%s", id, name))
    end

    return "Valid ids: " .. table.concat(parts, ", ")
end

---Returns the growth state distribution of the crops on the given field as text. Works on clients too.
function NotSoEasyDeveloperControls.getGrowthStateInfo(fieldId)
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
function NotSoEasyDeveloperControls.resolveFieldId(fieldIdStr, usage)
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
    local field = NotSoEasyDeveloperControls.getFieldAtPosition(x, z)
    if field == nil then
        return nil, "Not standing on a field, use: " .. usage
    end

    return field:getId()
end

---Client side convenience check, the server re-checks the sender.
function NotSoEasyDeveloperControls.getIsAllowed()
    local mission = g_currentMission
    return mission:getIsServer() or mission.isMasterUser
end

function NotSoEasyDeveloperControls.consoleCommandClear(_, fieldIdStr)
    if not NotSoEasyDeveloperControls.getIsAllowed() then
        return "Command not allowed"
    end

    local usage = "nseClearFertilizerState [fieldId]"
    local fieldId, err = NotSoEasyDeveloperControls.resolveFieldId(fieldIdStr, usage)
    if fieldId == nil then
        return err
    end

    if g_currentMission:getIsServer() then
        local _, message = NotSoEasyDeveloperControls.clearField(fieldId)
        return message
    end

    g_client:getServerConnection():sendEvent(NotSoEasyDeveloperControlsEvent.new(fieldId, NotSoEasyDeveloperControlsEvent.ACTION_CLEAR))

    return string.format("Requested fertilizer clear for field %d", fieldId)
end

-- nseSetGrowthState [fieldId] <state>: one argument is the state, two are fieldId and state.
function NotSoEasyDeveloperControls.consoleCommandSetGrowthState(_, arg1, arg2)
    if not NotSoEasyDeveloperControls.getIsAllowed() then
        return "Command not allowed"
    end

    local usage = "nseSetGrowthState [fieldId] <state>"
    local fieldIdStr, stateStr = arg1, arg2
    if arg2 == nil then
        fieldIdStr, stateStr = nil, arg1
    end

    local state = tonumber(stateStr)
    if state == nil or state < 1 or state > 255 or state ~= math.floor(state) then
        return "Invalid growth state. Use: " .. usage
    end

    local fieldId, err = NotSoEasyDeveloperControls.resolveFieldId(fieldIdStr, usage)
    if fieldId == nil then
        return err
    end

    if g_currentMission:getIsServer() then
        local _, message = NotSoEasyDeveloperControls.setGrowthState(fieldId, state)
        return message
    end

    g_client:getServerConnection():sendEvent(NotSoEasyDeveloperControlsEvent.new(fieldId, NotSoEasyDeveloperControlsEvent.ACTION_SET_GROWTH, state))

    return string.format("Requested growth state %d for field %d", state, fieldId)
end

-- nseSetGroundType <id>: sets the ground type of the field under the player.
function NotSoEasyDeveloperControls.consoleCommandSetGroundType(_, idStr)
    if not NotSoEasyDeveloperControls.getIsAllowed() then
        return "Command not allowed"
    end

    local usage = "nseSetGroundType <id>"
    local groundTypeId = tonumber(idStr)
    if groundTypeId == nil or FieldGroundType.getName(groundTypeId) == nil then
        return string.format("Invalid ground type id. Use: %s. %s", usage, NotSoEasyDeveloperControls.getGroundTypeList())
    end

    local fieldId, err = NotSoEasyDeveloperControls.resolveFieldId(nil, usage)
    if fieldId == nil then
        return err
    end

    if g_currentMission:getIsServer() then
        local _, message = NotSoEasyDeveloperControls.setGroundType(fieldId, groundTypeId)
        return message
    end

    g_client:getServerConnection():sendEvent(NotSoEasyDeveloperControlsEvent.new(fieldId, NotSoEasyDeveloperControlsEvent.ACTION_SET_GROUND_TYPE, groundTypeId))

    return string.format("Requested ground type %d for field %d", groundTypeId, fieldId)
end

function NotSoEasyDeveloperControls.consoleCommandGetGrowthState(_, fieldIdStr)
    local fieldId, err = NotSoEasyDeveloperControls.resolveFieldId(fieldIdStr, "nseGetGrowthState [fieldId]")
    if fieldId == nil then
        return err
    end

    return NotSoEasyDeveloperControls.getGrowthStateInfo(fieldId)
end

addConsoleCommand("nseClearFertilizerState", "Clears the fertilizer layer from a field (admin only). Without argument uses the field under the player.", "consoleCommandClear", NotSoEasyDeveloperControls, "[fieldId]")
addConsoleCommand("nseSetGrowthState", "Sets the growth state of the crops on a field (admin only). With one argument uses the field under the player.", "consoleCommandSetGrowthState", NotSoEasyDeveloperControls, "[fieldId]; <state>")
addConsoleCommand("nseSetGroundType", "Sets the ground type of the field the player is standing on (admin only). Ids: 1=NONE, 2=STUBBLE_TILLAGE, 3=CULTIVATED, 4=SEEDBED, 5=PLOWED, 6=ROLLED_SEEDBED, 7=RIDGE, 8=SOWN, 9=DIRECT_SOWN, 10=PLANTED, 11=RIDGE_SOWN, 12=ROLLER_LINES, 13=HARVEST_READY, 14=HARVEST_READY_OTHER, 15=GRASS, 16=GRASS_CUT.", "consoleCommandSetGroundType", NotSoEasyDeveloperControls, "<id>")
addConsoleCommand("nseGetGrowthState", "Shows the growth states of the crops on a field. Without argument uses the field under the player.", "consoleCommandGetGrowthState", NotSoEasyDeveloperControls, "[fieldId]")
