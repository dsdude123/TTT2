---- Customized scoring

local math = math
local string = string
local table = table
local pairs = pairs

SCORE = SCORE or {}
SCORE.Events = SCORE.Events or {}

-- One might wonder why all the key names in the event tables are so annoyingly
-- short. Well, the serialisation module in gmod (glon) does not do any
-- compression. At all. This means the difference between all events having a
-- "time_added" key versus a "t" key is very significant for the amount of data
-- we need to send. It's a pain, but I'm not going to code my own compression,
-- so doing it manually is the only way.

-- One decent way to reduce data sent turned out to be rounding the time floats.
-- We don't actually need to know about 10000ths of seconds after all.

function SCORE:AddEvent(entry, t_override)
	entry["t"] = math.Round(t_override or CurTime(), 2)
	
	table.insert(self.Events, entry)
end

local function CopyDmg(dmg)
	local wep = util.WeaponFromDamage(dmg)

	-- t = type, a = amount, g = gun, h = headshot
	local d = {}

	-- util.TableToJSON doesn't handle large integers properly
	d.t = tostring(dmg:GetDamageType())
	d.a = dmg:GetDamage()
	d.h = false

	if wep then
		local id = WepToEnum(wep)
		if id then
			d.g = id
		else
			-- we can convert each standard TTT weapon name to a preset ID, but
			-- that's not workable with custom SWEPs from people, so we'll just
			-- have to pay the byte tax there
			d.g = wep:GetClass()
		end
	else
		local infl = dmg:GetInflictor()
		
		if IsValid(infl) and infl.ScoreName then
			d.n = infl.ScoreName
		end
	end

	return d
end

function SCORE:HandleKill(victim, attacker, dmginfo)
	if not IsValid(victim) or not victim:IsPlayer() then return end

	local e = {
		id = EVENT_KILL,
		att = {ni = "", sid = -1, r = -1},
		vic = {ni = victim:Nick(), sid = victim:SteamID(), r = victim:GetRole()},
		dmg = CopyDmg(dmginfo)
	}

	e.dmg.h = victim.was_headshot

	if IsValid(attacker) and attacker:IsPlayer() then
		e.att.ni = attacker:Nick()
		e.att.sid = attacker:SteamID()
		e.att.r = attacker:GetRole()
	end
	
	hook.Run("TTT2_ModifyScoringEvent", e, {victim = victim, attacker = attacker, dmginfo = dmginfo})

	if IsValid(attacker) and attacker:IsPlayer() then
		-- If a traitor gets himself killed by another traitor's C4, it's his own
		-- damn fault for ignoring the indicator.
		if dmginfo:IsExplosionDamage() and GetRoleByIndex(e.att.r).team == TEAM_TRAITOR and GetRoleByIndex(e.vic.r).team == TEAM_TRAITOR then
			local infl = dmginfo:GetInflictor()
			
			if IsValid(infl) and infl:GetClass() == "ttt_c4" then
				e.att = table.Copy(e.vic)
			end
		end
	end
	
	self:AddEvent(e)
end

function SCORE:HandleSpawn(ply)
	if ply:Team() == TEAM_TERROR then
		self:AddEvent({id = EVENT_SPAWN, ni = ply:Nick(), sid = ply:SteamID()})
	end
end

function SCORE:HandleSelection()
	local tmp = {}

	for _, v in pairs(ROLES) do
		if v ~= ROLES.INNOCENT then
			tmp[v.index] = {}
		end
	end
	
	for _, ply in ipairs(player.GetAll()) do
		-- no innos
		if ply:GetRole() ~= ROLES.INNOCENT.index then
			table.insert(tmp[ply:GetRole()], ply:SteamID())
		end
	end

	self:AddEvent({id = EVENT_SELECTED, roleTbl = tmp})
end

function SCORE:HandleBodyFound(finder, found)
	self:AddEvent({id = EVENT_BODYFOUND, ni = finder:Nick(), sid = finder:SteamID(), b = found:Nick()})
end

function SCORE:HandleC4Explosion(planter, arm_time, exp_time)
	local nick = "Someone"
	
	if IsValid(planter) and planter:IsPlayer() then
		nick = planter:Nick()
	end

	self:AddEvent({id = EVENT_C4PLANT, ni = nick}, arm_time)
	self:AddEvent({id = EVENT_C4EXPLODE, ni = nick}, exp_time)
end

function SCORE:HandleC4Disarm(disarmer, owner, success)
	if disarmer == owner then return end
	
	if not IsValid(disarmer) then return end

	local ev = {
		id = EVENT_C4DISARM,
		ni = disarmer:Nick(),
		s	= success
	}

	if IsValid(owner) then
		ev.own = owner:Nick()
	end

	self:AddEvent(ev)
end

function SCORE:HandleCreditFound(finder, found_nick, credits)
	self:AddEvent({id = EVENT_CREDITFOUND, ni = finder:Nick(), sid = finder:SteamID(), b = found_nick, cr = credits})
end

function SCORE:ApplyEventLogScores(wintype, winrole)
	local scores = {}
	local tmp = {}

	for _, v in pairs(ROLES) do
		if v ~= ROLES.INNOCENT then
			tmp[v.index] = {}
		end
	end
	
	for _, ply in ipairs(player.GetAll()) do
		scores[ply:SteamID()] = {}
		
		if ply:GetRole() ~= ROLES.INNOCENT.index then
			table.insert(tmp[ply:GetRole()], ply:SteamID())
		end
	end

	-- individual scores, and count those left alive
	--local alive = {traitors = 0, not_traitors = 0}
	--local dead = {traitors = 0, not_traitors = 0}
	local scored_log = ScoreEventLog(self.Events, scores, tmp)
	local ply = nil
	
	for sid, s in pairs(scored_log) do
		ply = player.GetBySteamID(sid)
		
		if ply and ply:ShouldScore() then
			ply:AddFrags(KillsToPoints(s))
		end
	end

	-- team scores
	local bonus = ScoreTeamBonus(scored_log, wintype, winrole)

	for sid, s in pairs(scored_log) do
		ply = player.GetBySteamID(sid)
		
		if ply and IsValid(ply) then
			local team = hook.Run("TTT2_ScoringGettingRole", ply) or ply:GetRoleData()
			team = team.team
		
			if ply:ShouldScore() then
				ply:AddFrags(bonus[team])
			end
		end
	end

	-- count deaths
	for _, e in pairs(self.Events) do
		if e.id == EVENT_KILL then
			local victim = player.GetBySteamID(e.vic.sid)
			
			if IsValid(victim) and victim:ShouldScore() then
				victim:AddDeaths(1)
			end
		end
	end
end

function SCORE:RoundStateChange(newstate)
	self:AddEvent({id = EVENT_GAME, state = newstate})
end

function SCORE:RoundComplete(wintype, winrole)
	self:AddEvent({id = EVENT_FINISH, win = wintype, wr = winrole})
end

function SCORE:Reset()
	self.Events = {}
end

local function SortEvents(events)
	-- sort events on time
	table.sort(events, function(a, b)
		if not b or not a then return false end
		
		return a.t and b.t and a.t < b.t
	end)
	
	return events
end

local function EncodeForStream(events)
	events = SortEvents(events)

	-- may want to filter out data later
	-- just serialize for now

	local result = util.TableToJSON(events)
	if not result then
		ErrorNoHalt("Round report event encoding failed!\n")
		
		return false
	else
		return result
	end
end

function SCORE:StreamToClients()
	local s = EncodeForStream(self.Events)
	
	if not s then
		return -- error occurred
	end

	-- divide into happy lil bits.
	-- this was necessary with user messages, now it's
	-- a just-in-case thing if a round somehow manages to be > 64K
	local cut = {}
	local max = 65500
	
	while #s ~= 0 do
		local bit = string.sub(s, 1, max - 1)
		
		table.insert(cut, bit)

		s = string.sub(s, max, -1)
	end

	local parts = #cut
	
	for k, bit in ipairs(cut) do
		net.Start("TTT_ReportStream")
		net.WriteBit((k ~= parts)) -- continuation bit, 1 if there's more coming
		net.WriteString(bit)
		net.Broadcast()
	end
end
