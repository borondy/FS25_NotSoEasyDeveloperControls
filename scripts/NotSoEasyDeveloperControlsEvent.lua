-- Client -> server request to change the ground state of one field (clear fertilizer layer or set crop growth state).
-- The server re-checks that the sender is an admin, the client-side check in the console command is only a convenience.

NotSoEasyDeveloperControlsEvent = {}
local NotSoEasyDeveloperControlsEvent_mt = Class(NotSoEasyDeveloperControlsEvent, Event)

InitEventClass(NotSoEasyDeveloperControlsEvent, "NotSoEasyDeveloperControlsEvent")

NotSoEasyDeveloperControlsEvent.ACTION_CLEAR = 1
NotSoEasyDeveloperControlsEvent.ACTION_SET_GROWTH = 2
NotSoEasyDeveloperControlsEvent.ACTION_SET_GROUND_TYPE = 3

-- actions that carry a value (growth state or ground type id)
local function hasValue(action)
    return action == NotSoEasyDeveloperControlsEvent.ACTION_SET_GROWTH or action == NotSoEasyDeveloperControlsEvent.ACTION_SET_GROUND_TYPE
end

function NotSoEasyDeveloperControlsEvent.emptyNew()
    return Event.new(NotSoEasyDeveloperControlsEvent_mt)
end

function NotSoEasyDeveloperControlsEvent.new(fieldId, action, state)
    local self = NotSoEasyDeveloperControlsEvent.emptyNew()
    self.fieldId = fieldId
    self.action = action
    self.state = state or 0
    return self
end

function NotSoEasyDeveloperControlsEvent:readStream(streamId, connection)
    self.fieldId = streamReadUInt16(streamId)
    self.action = streamReadUInt8(streamId)
    if hasValue(self.action) then
        self.state = streamReadUInt8(streamId)
    end
    self:run(connection)
end

function NotSoEasyDeveloperControlsEvent:writeStream(streamId, connection)
    streamWriteUInt16(streamId, self.fieldId)
    streamWriteUInt8(streamId, self.action)
    if hasValue(self.action) then
        streamWriteUInt8(streamId, self.state)
    end
end

function NotSoEasyDeveloperControlsEvent:run(connection)
    -- only the server handles requests, a client never receives this event
    if connection:getIsServer() then
        return
    end

    local user = g_currentMission.userManager:getUserByConnection(connection)
    if user == nil or not user:getIsMasterUser() then
        Logging.warning("[NotSoEasyDeveloperControls] Rejected request for field %d from a non-admin connection.", self.fieldId)
        return
    end

    local _, message
    if self.action == NotSoEasyDeveloperControlsEvent.ACTION_CLEAR then
        _, message = NotSoEasyDeveloperControls.clearField(self.fieldId)
    elseif self.action == NotSoEasyDeveloperControlsEvent.ACTION_SET_GROWTH then
        if self.state < 1 then
            Logging.warning("[NotSoEasyDeveloperControls] Rejected invalid growth state %d for field %d.", self.state, self.fieldId)
            return
        end
        _, message = NotSoEasyDeveloperControls.setGrowthState(self.fieldId, self.state)
    elseif self.action == NotSoEasyDeveloperControlsEvent.ACTION_SET_GROUND_TYPE then
        _, message = NotSoEasyDeveloperControls.setGroundType(self.fieldId, self.state)
    else
        Logging.warning("[NotSoEasyDeveloperControls] Unknown action %d for field %d.", self.action, self.fieldId)
        return
    end

    Logging.info("[NotSoEasyDeveloperControls] %s", message)
end
