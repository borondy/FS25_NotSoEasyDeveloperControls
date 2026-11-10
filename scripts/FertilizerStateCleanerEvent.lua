-- Client -> server request to change the ground state of one field (clear fertilizer layer or set crop growth state).
-- The server re-checks that the sender is an admin, the client-side check in the console command is only a convenience.

FertilizerStateCleanerEvent = {}
local FertilizerStateCleanerEvent_mt = Class(FertilizerStateCleanerEvent, Event)

InitEventClass(FertilizerStateCleanerEvent, "FertilizerStateCleanerEvent")

FertilizerStateCleanerEvent.ACTION_CLEAR = 1
FertilizerStateCleanerEvent.ACTION_SET_GROWTH = 2

function FertilizerStateCleanerEvent.emptyNew()
    return Event.new(FertilizerStateCleanerEvent_mt)
end

function FertilizerStateCleanerEvent.new(fieldId, action, state)
    local self = FertilizerStateCleanerEvent.emptyNew()
    self.fieldId = fieldId
    self.action = action
    self.state = state or 0
    return self
end

function FertilizerStateCleanerEvent:readStream(streamId, connection)
    self.fieldId = streamReadUInt16(streamId)
    self.action = streamReadUInt8(streamId)
    if self.action == FertilizerStateCleanerEvent.ACTION_SET_GROWTH then
        self.state = streamReadUInt8(streamId)
    end
    self:run(connection)
end

function FertilizerStateCleanerEvent:writeStream(streamId, connection)
    streamWriteUInt16(streamId, self.fieldId)
    streamWriteUInt8(streamId, self.action)
    if self.action == FertilizerStateCleanerEvent.ACTION_SET_GROWTH then
        streamWriteUInt8(streamId, self.state)
    end
end

function FertilizerStateCleanerEvent:run(connection)
    -- only the server handles requests, a client never receives this event
    if connection:getIsServer() then
        return
    end

    local user = g_currentMission.userManager:getUserByConnection(connection)
    if user == nil or not user:getIsMasterUser() then
        Logging.warning("[FertilizerStateCleaner] Rejected request for field %d from a non-admin connection.", self.fieldId)
        return
    end

    local _, message
    if self.action == FertilizerStateCleanerEvent.ACTION_CLEAR then
        _, message = FertilizerStateCleaner.clearField(self.fieldId)
    elseif self.action == FertilizerStateCleanerEvent.ACTION_SET_GROWTH then
        if self.state < 1 then
            Logging.warning("[FertilizerStateCleaner] Rejected invalid growth state %d for field %d.", self.state, self.fieldId)
            return
        end
        _, message = FertilizerStateCleaner.setGrowthState(self.fieldId, self.state)
    else
        Logging.warning("[FertilizerStateCleaner] Unknown action %d for field %d.", self.action, self.fieldId)
        return
    end

    Logging.info("[FertilizerStateCleaner] %s", message)
end
