Scriptname AIAgentNSFWSexLab Hidden
; Optional SexLab adapter. Call only after the common HasSexLab/UseSexLabEngine guard.
; Keep SexLab-specific types out of the shared registration and command scripts.

SexLabFramework Function GetSexLab() global
    return Game.GetFormFromFile(0xD62, "SexLab.esm") as SexLabFramework
EndFunction

Actor[] Function NormalizeSexLabActors(SexLabFramework slf, Actor[] actors) global
    ; SexLab StartSex defines slot 0 as the passive position and its animation
    ; registry generally expects female positions first. SHARMAT used to pass
    ; [speaker, target] unchanged, which made the initiator accidentally decide
    ; the passive/active assignment before SexLab selected an animation.
    if slf == None || actors.Length < 2
        return actors
    endif

    Actor[] sorted = slf.SortActors(actors, true)
    if sorted.Length == actors.Length
        Debug.Trace("[CHIM-NSFW SceneEngine] SexLab role sort: " + AIAgentNSFWSceneEngine.RosterNames(actors) + " -> " + AIAgentNSFWSceneEngine.RosterNames(sorted) + " (slot 0 = passive, female first)")
        return sorted
    endif

    Debug.Trace("[CHIM-NSFW SceneEngine] SexLab role sort failed; keeping original roster " + AIAgentNSFWSceneEngine.RosterNames(actors))
    return actors
EndFunction

bool Function SexLabRosterIsReleased(SexLabFramework slf, Actor[] actors) global
    if slf == None
        return false
    endif
    int i = 0
    while i < actors.Length
        if actors[i] == None || slf.FindActorController(actors[i]) >= 0
            return false
        endif
        i += 1
    endwhile
    return true
EndFunction

bool Function StopSexLabControllerAndWait(SexLabFramework slf, sslThreadController ctrl, int threadID, Actor[] actors) global
    if slf == None || ctrl == None
        return false
    endif
    ctrl.EndAnimation(true)
    int guard = 0
    while guard < 50 && !SexLabRosterIsReleased(slf, actors)
        Utility.Wait(0.2)
        guard += 1
    endwhile
    if !SexLabRosterIsReleased(slf, actors)
        Debug.Trace("[CHIM-NSFW SceneEngine] SexLab restart aborted: controller " + threadID + " did not release its actors")
        return false
    endif
    return true
EndFunction

bool Function StartOrJoinSexLab(Actor akSpeaker, Actor akTarget, bool bAllowJoin, string sceneAct = "") global
    SexLabFramework slf = GetSexLab()
    if slf == None
        return false
    endif
    int speakerThread = slf.FindActorController(akSpeaker)
    int targetThread = slf.FindActorController(akTarget)
    int activeThread = speakerThread
    if activeThread < 0
        activeThread = targetThread
    endif

    if activeThread < 0
        Actor[] pair = new Actor[2]
        pair[0] = akSpeaker
        pair[1] = akTarget
        Debug.Trace("[CHIM-NSFW SceneEngine] SexLab: starting new scene " + akSpeaker.GetDisplayName() + " + " + akTarget.GetDisplayName() + " act=" + sceneAct)
        return StartSexLabScene(slf, pair, sceneAct)
    endif

    if speakerThread >= 0 && targetThread >= 0 && speakerThread != targetThread
        Debug.Trace("[CHIM-NSFW SceneEngine] SexLab join aborted: actors belong to different live controllers (" + speakerThread + ", " + targetThread + ")")
        return false
    endif

    ; Both already in the SAME SexLab scene -> SHIFT to the requested act (parity with the OStim
    ; ShiftOStimSceneToAct path). SexLab has no in-thread WarpTo, so ShiftSexLabScene does a quick stop+restart
    ; with animations matching the new act. Same actors, new act (e.g. she asks for a blowjob mid-scene).
    if speakerThread >= 0 && targetThread >= 0 && speakerThread == targetThread
        if sceneAct != ""
            return ShiftSexLabScene(slf, speakerThread, sceneAct)
        endif
        return true
    endif

    if !bAllowJoin
        return false
    endif

    Actor joiner = akSpeaker
    if speakerThread >= 0
        joiner = akTarget
    endif
    Debug.Trace("[CHIM-NSFW SceneEngine] SexLab: joining controller " + activeThread + " with " + joiner.GetDisplayName())
    return AddActorToSexLabThread(slf, activeThread, joiner)
EndFunction

bool Function StartSexLabScene(SexLabFramework slf, Actor[] actors, string sceneAct = "") global
    if AIAgentNSFWSceneEngine.RosterContainsProtectedMinor(actors)
        Debug.Trace("[CHIM-NSFW SceneEngine] SexLab start blocked: protected minor in actor roster")
        return false
    endif
    actors = NormalizeSexLabActors(slf, actors)
    int[] genders = slf.GenderCount(actors)
    int males = genders[0]
    int females = genders[1]
    sslBaseAnimation[] anims = slf.GetAnimationsByDefault(males, females) ; default baseline (always valid)
    string tags = AIAgentNSFWSceneEngine.SexLabTagsForAct(sceneAct)
    sslBaseAnimation[] tagged
    int taggedCount = 0
    if tags != ""
        tagged = slf.GetAnimationsByDefaultTags(males, females, false, false, true, tags, "", false)
        if tagged
            taggedCount = tagged.Length
        endif
        if taggedCount < 1 && sceneAct == "bloodfeed"
            ; No vampire-tagged SexLab animations installed (vanilla registry has none) - prefer an embrace-style
            ; foreplay/leadin scene over a random default so the feed still reads as a neck bite (fix 2026-07-01)
            tagged = slf.GetAnimationsByDefaultTags(males, females, false, false, true, "Foreplay,LeadIn", "", false)
            if tagged
                taggedCount = tagged.Length
            endif
        endif
    endif
    if taggedCount < 1 && !AIAgentNSFWSceneEngine.OStimActAvoidsSexualFallback(sceneAct) && AIAgentNSFWSceneEngine.RosterIsPlayerFemaleFemalePair(actors)
        tagged = slf.GetAnimationsByDefaultTags(males, females, false, false, true, "Lesbian,Cunnilingus", "", false)
        if tagged
            taggedCount = tagged.Length
        endif
        if taggedCount >= 1
            Debug.Trace("[CHIM-NSFW SceneEngine] SexLab FF player pair: using lesbian/cunnilingus animations")
        endif
    endif
    if taggedCount >= 1
        anims = tagged ; steer to the requested act when matches exist
    endif
    return slf.StartSex(actors, anims) >= 0
EndFunction

bool Function AddActorToSexLabThread(SexLabFramework slf, int threadID, Actor joiner) global
    if slf == None || joiner == None
        return false
    endif
    sslThreadController ctrl = slf.GetController(threadID)
    if ctrl == None
        return false
    endif
    Actor[] current = ctrl.Positions
    if current.Length < 1 || current.Length >= 5
        return false
    endif
    if current.Find(joiner) >= 0
        return true ; already in this scene - nothing to do
    endif
    if slf.FindActorController(joiner) >= 0
        Debug.Trace("[CHIM-NSFW SceneEngine] SexLab join aborted: joiner already belongs to a different live controller")
        return false
    endif
    Actor[] combined = PapyrusUtil.PushActor(current, joiner)
    if !StopSexLabControllerAndWait(slf, ctrl, threadID, combined)
        return false
    endif
    return StartSexLabScene(slf, combined, "")
EndFunction

bool Function ShiftSexLabScene(SexLabFramework slf, int threadID, string sceneAct) global
    sslThreadController ctrl = slf.GetController(threadID)
    if ctrl == None
        return false
    endif
    Actor[] liveActors = ctrl.Positions
    if liveActors.Length < 1
        return false
    endif
    ; SortActors may reorder the array it receives. Copy live controller positions first so role
    ; normalization cannot mutate the active controller's roster before teardown completes.
    Actor[] actors = PapyrusUtil.ActorArray(0)
    int actorIndex = 0
    while actorIndex < liveActors.Length
        if liveActors[actorIndex] == None
            Debug.Trace("[CHIM-NSFW SceneEngine] SexLab shift aborted: live controller returned an invalid actor slot")
            return false
        endif
        actors = PapyrusUtil.PushActor(actors, liveActors[actorIndex])
        actorIndex += 1
    endwhile
    actors = NormalizeSexLabActors(slf, actors)
    int[] genders = slf.GenderCount(actors)
    int males = genders[0]
    int females = genders[1]
    string tags = AIAgentNSFWSceneEngine.SexLabTagsForAct(sceneAct)
    if tags == ""
        return false ; unknown/empty act - nothing to steer to, leave the scene as-is
    endif
    sslBaseAnimation[] tagged = slf.GetAnimationsByDefaultTags(males, females, false, false, true, tags, "", false)
    if tagged.Length < 1 && sceneAct == "bloodfeed"
        ; same embrace-style fallback as StartSexLabScene (fix 2026-07-01)
        tagged = slf.GetAnimationsByDefaultTags(males, females, false, false, true, "Foreplay,LeadIn", "", false)
    endif
    if tagged.Length < 1
        Debug.Trace("[CHIM-NSFW SceneEngine] SexLab shift: no animation matched act=" + sceneAct + " - leaving current scene")
        return false
    endif
    Debug.Trace("[CHIM-NSFW SceneEngine] SexLab shift: thread " + threadID + " -> act=" + sceneAct + " (" + tagged.Length + " anims)")
    if !StopSexLabControllerAndWait(slf, ctrl, threadID, actors)
        return false
    endif
    return slf.StartSex(actors, tagged) >= 0
EndFunction

bool Function StartSoloScene(Actor akActor, string sceneAct = "") global
    SexLabFramework slf = GetSexLab()
    if slf != None
        if slf.FindActorController(akActor) >= 0
            return true ; already in a scene
        endif
        Actor[] solo = new Actor[1]
        solo[0] = akActor
        Debug.Trace("[CHIM-NSFW SceneEngine] SexLab: starting solo scene " + akActor.GetDisplayName() + " act=" + sceneAct)
        return StartSexLabScene(slf, solo, sceneAct)
    endif
    Debug.Trace("[CHIM-NSFW SceneEngine] No OStim or SexLab detected (solo)")
    return false
EndFunction

bool Function StartGroupScene(Actor[] group, string sceneAct = "") global
    int i = 0
    SexLabFramework slf = GetSexLab()
    if slf != None
        int liveController = -1
        bool conflictingControllers = false
        i = 0
        while i < group.Length
            int actorController = slf.FindActorController(group[i])
            if actorController >= 0
                if liveController < 0
                    liveController = actorController
                elseif actorController != liveController
                    conflictingControllers = true
                endif
            endif
            i += 1
        endwhile
        if conflictingControllers
            Debug.Trace("[CHIM-NSFW SceneEngine] SexLab group merge aborted: requested actors belong to different live controllers")
            return false
        endif
        if liveController >= 0
            sslThreadController groupCtrl = slf.GetController(liveController)
            if groupCtrl == None
                return false
            endif
            Actor[] combinedS = groupCtrl.Positions
            bool mergeOverflowS = false
            i = 0
            while i < group.Length
                if combinedS.Find(group[i]) < 0
                    if combinedS.Length < 5
                        combinedS = PapyrusUtil.PushActor(combinedS, group[i])
                    else
                        mergeOverflowS = true
                    endif
                endif
                i += 1
            endwhile
            if mergeOverflowS
                Debug.Trace("[CHIM-NSFW SceneEngine] SexLab group merge aborted: combined roster exceeds five actors")
                return false
            endif
            if !StopSexLabControllerAndWait(slf, groupCtrl, liveController, combinedS)
                return false
            endif
            Debug.Trace("[CHIM-NSFW SceneEngine] SexLab: group merge from controller " + liveController + " -> " + combinedS.Length + " actors")
            return StartSexLabScene(slf, combinedS, sceneAct)
        endif
        Debug.Trace("[CHIM-NSFW SceneEngine] SexLab: fresh group scene with " + group.Length + " actors, act=" + sceneAct)
        return StartSexLabScene(slf, group, sceneAct)
    endif
    Debug.Trace("[CHIM-NSFW SceneEngine] No OStim or SexLab detected (group)")
    return false
EndFunction

bool Function LeaveScene(Actor akLeaver) global
    SexLabFramework slf = GetSexLab()
    if slf != None
        int cid = slf.FindActorController(akLeaver)
        if cid < 0
            return false
        endif
        sslThreadController ctrl = slf.GetController(cid)
        if ctrl == None
            return false
        endif
        Actor[] currentS = ctrl.Positions
        if !StopSexLabControllerAndWait(slf, ctrl, cid, currentS)
            return false
        endif
        if currentS.Length <= 2
            return true
        endif
        Actor[] restS = PapyrusUtil.ActorArray(0)
        int j = 0
        while j < currentS.Length
            if currentS[j] != None && currentS[j] != akLeaver
                restS = PapyrusUtil.PushActor(restS, currentS[j])
            endif
            j += 1
        endwhile
        if restS.Length < 2
            return true
        endif
        Debug.Trace("[CHIM-NSFW SceneEngine] SexLab: " + akLeaver.GetDisplayName() + " left; restarting with " + restS.Length + " actors")
        return StartSexLabScene(slf, restS, "")
    endif
    return false
EndFunction

Function OnSexLabAnimStart(AIAgentNSFW bridge, int tid, bool HasPlayer) global
	if !AIAgentNSFWSceneEngine.UseSexLabEngine()
		return
	endif
	SexLabFramework SexLab = SexLabUtil.GetAPI()
	if (!SexLab)
		return
	endif
	sslThreadController controller = SexLab.GetController(tid)
	if (!controller)
		return
	endif
	Actor[] actors = controller.Positions
	if (actors.Length < 1)
		return
	endif

	Actor sceneVictim = controller.GetVictim()
	string sceneID = controller.Animation.Name
	string sceneTags = PapyrusUtil.StringJoin(controller.Animation.GetTags(), ",") ; GetTags() is string[]; the bare cast produced "[A, B, C]" which broke server CSV tag parsing (fix 2026-07-01)
	string actorList = ""
	Actor firstNpc = None
	int i = 0
	while (i < actors.Length)
		string actorRoleSuffix = ""
		if (sceneVictim != None)
			if (actors[i] == sceneVictim)
				actorRoleSuffix = "^victim,forced"
			else
				actorRoleSuffix = "^aggressor,forced"
			endif
		endif
		actorList = actorList + "/" + actors[i].GetDisplayName() + actorRoleSuffix
		if (actors[i].GetFormID() != 0x14)
			if (firstNpc == None)
				firstNpc = actors[i]
			endif
			AIAgentFunctions.setAnimationBusy(1, actors[i].GetDisplayName())
		endif
		i += 1
	endWhile
	if (firstNpc == None)
		return
	endif

	; NPC-to-NPC SexLab scene: emit the rich relationship-tier event first (mirrors OStimThreadStart) so the server
	; sets is_npc_scene/npc_scene_partner and uses the NPC-to-NPC relationship/tier prompts (parity with OStim).
	if (!HasPlayer && actors.Length >= 2)
		int npc1ToNpc2Rank = actors[0].GetRelationshipRank(actors[1])
		int npc2ToNpc1Rank = actors[1].GetRelationshipRank(actors[0])
		string npcSceneData = actors[0].GetDisplayName() + "^" + actors[1].GetDisplayName() + "^" + tid + "^" + sceneID + "^" + npc1ToNpc2Rank + "^" + npc2ToNpc1Rank
		bridge.RequestNpcSceneTurn(actors, npcSceneData, "SexLabNpcSceneStart", tid)
		Debug.Trace("[CHIM-NSFW] SexLab NPC-only scene start tid=" + tid + " requested ext_nsfw_npc_scene")
		return
	endif

	; SOLO NPC scene (masturbation): keep it OFF the player-scene route (fix 2026-07-01, OStim parity - a solo
	; scene fires no player-scene event; the server's canonicalization needs >=2 actors anyway).
	if (!HasPlayer)
		return
	endif

	bridge.SendPlayerBodyState()

	; Matches the ext_nsfw_sexcene wire OStimStart uses: SceneID/tags/SceneID/actors
	; The normal scene turn owns the tier-3 consent decision through the
	; AcceptSex/RefuseSex toolset. Do not emit a second narrator-directed bark.
	string sceneData = AIAgentNSFWSceneEngine.AppendFwTag(sceneID + "/" + sceneTags + "/" + sceneID + actorList, "sexlab")
	AIAgentFunctions.requestMessageForActor(sceneData, "ext_nsfw_sexcene", firstNpc.GetDisplayName())
	Debug.Trace("[CHIM-NSFW] SexLab scene start tid=" + tid + " player=" + HasPlayer)
EndFunction

Function OnSexLabStageStart(AIAgentNSFW bridge, int tid, bool HasPlayer) global
	if !AIAgentNSFWSceneEngine.UseSexLabEngine()
		return
	endif
	SexLabFramework SexLab = SexLabUtil.GetAPI()
	if (!SexLab)
		return
	endif
	sslThreadController controller = SexLab.GetController(tid)
	if (!controller)
		return
	endif
	Actor[] actors = controller.Positions
	if (actors.Length < 1)
		return
	endif

	; Scene awareness for ALL scenes (incl NPC-to-NPC) - no speech styles, just context
	Actor sceneVictim = controller.GetVictim()
	string sceneID = controller.Animation.Name
	string sceneTags = PapyrusUtil.StringJoin(controller.Animation.GetTags(), ",") ; GetTags() is string[]; the bare cast produced "[A, B, C]" which broke server CSV tag parsing (fix 2026-07-01)
	string stageDesc = controller.Animation.FetchStage(controller.Stage)[0]
	string actorList = ""
	; FORWARD order (fix 2026-07-01): the reverse loop stored raw_scene_actor_slots backwards vs Positions,
	; so the server's slot->name lookup could name the wrong actor on stage updates.
	int i = 0
	while (i < actors.Length)
		string actorRoleSuffix = ""
		if (sceneVictim != None)
			if (actors[i] == sceneVictim)
				actorRoleSuffix = "^victim,forced"
			else
				actorRoleSuffix = "^aggressor,forced"
			endif
		endif
		actorList = actorList + "/" + actors[i].GetDisplayName() + actorRoleSuffix
		if (actors[i].GetFormID() != 0x14)
			if (SexLab.isMouthOpen(actors[i]))
				AIAgentFunctions.setLocked(1, actors[i].GetDisplayName())
			else
				AIAgentFunctions.setLocked(0, actors[i].GetDisplayName())
			endif
		endif
		i += 1
	endWhile
	; NPC-only stages stay on the NPC-to-NPC route and request one participant response.
	if (!HasPlayer && actors.Length >= 2)
		int npc1ToNpc2Rank = actors[0].GetRelationshipRank(actors[1])
		int npc2ToNpc1Rank = actors[1].GetRelationshipRank(actors[0])
		string stageSceneID = sceneID + "_stage_" + controller.Stage
		string npcSceneData = actors[0].GetDisplayName() + "^" + actors[1].GetDisplayName() + "^" + tid + "^" + stageSceneID + "^" + npc1ToNpc2Rank + "^" + npc2ToNpc1Rank
		bridge.RequestNpcSceneTurn(actors, npcSceneData, "SexLabNpcStage", tid)
		return
	endif

	; SOLO NPC stage: off the player-scene route (fix 2026-07-01, mirrors the scene-start guard)
	if (!HasPlayer)
		return
	endif

	; Exactly one route for the stage. Prefer a mouth-free NPC. If every NPC is mouth-busy,
	; retain the canonical state event without also submitting a second directed request.
	string sceneData = AIAgentNSFWSceneEngine.AppendFwTag(sceneID + "/" + sceneTags + "/" + stageDesc + actorList, "sexlab")
	Actor[] sorted = SexLab.SortActors(actors, false)
	i = sorted.Length
	Actor participantTalk = None
	while (i > 0)
		i -= 1
		if (sorted[i].GetFormID() != 0x14 && !SexLab.isMouthOpen(sorted[i]))
			participantTalk = sorted[i]
			i = 0
		endif
	endWhile
	if participantTalk != None
		AIAgentFunctions.requestMessageForActor(sceneData, "ext_nsfw_sexcene", participantTalk.GetDisplayName())
		Debug.Trace("[CHIM-NSFW] SexLab stage routed once to " + participantTalk.GetDisplayName())
	else
		AIAgentFunctions.logMessage(sceneData, "info_sexscene")
	endif
EndFunction

Function OnSexLabActorOrgasm(AIAgentNSFW bridge, Form akActor, int FullEnjoyment, int Orgasms) global
	if !AIAgentNSFWSceneEngine.UseSexLabEngine()
		return
	endif
	Actor orgasmer = akActor as Actor
	if (!orgasmer)
		return
	endif
	SexLabFramework SexLab = SexLabUtil.GetAPI()
	if (!SexLab)
		return
	endif
	int tid = SexLab.FindActorController(orgasmer)
	if (tid < 0)
		return
	endif
	sslThreadController controller = SexLab.GetController(tid)
	if (!controller)
		return
	endif
	Actor[] actors = controller.Positions
	if (actors.Length < 1)
		return
	endif

	string sceneID = controller.Animation.Name
	; Action-type field for the server (fix 2026-07-01, OStim parity): SexLab has no per-action metadata, but the
	; animation TAGS csv substring-matches the same server act table (blowjob/anal/handjob/...), reviving the
	; orgasm-location phrase + act-specific cues in SexLab scenes.
	string slOrgasmTags = PapyrusUtil.StringJoin(controller.Animation.GetTags(), ",")
	bool sceneHasPlayer = false
	int orgasmerIndex = 0
	string partnerName = ""
	int k = 0
	while (k < actors.Length)
		if (actors[k].GetFormID() == 0x14)
			sceneHasPlayer = true
		endif
		if (actors[k] == orgasmer)
			orgasmerIndex = k
		elseif (partnerName == "")
			partnerName = actors[k].GetDisplayName()
		endif
		k += 1
	endWhile

	if (orgasmer.GetFormID() == 0x14)
		; Player came - everyone in THIS scene hears it (fan out to every non-player actor)
		string playerData = AIAgentNSFWSceneEngine.AppendFwTag("PLAYER_ORGASM/" + sceneID + "/" + orgasmerIndex + "/" + partnerName + "/" + slOrgasmTags, "sexlab") ; [3]=partner [4]=action (fix 2026-07-01: was the player's own name at [3] and no action field)
		int m = 0
		while (m < actors.Length)
			if (actors[m].GetFormID() != 0x14)
				AIAgentFunctions.requestMessageForActor(playerData, "ext_nsfw_orgasm", actors[m].GetDisplayName())
			endif
			m += 1
		endWhile
	else
		; NPC came - tell THAT NPC. Player scene -> ext_nsfw_orgasm; NPC-to-NPC -> ext_nsfw_npc_orgasm
		string orgasmData = orgasmer.GetDisplayName() + "/" + sceneID + "/" + orgasmerIndex
		if (partnerName != "")
			orgasmData = orgasmData + "/" + partnerName + "/" + slOrgasmTags ; [4]=action (fix 2026-07-01, OStim parity)
		endif
		if (sceneHasPlayer)
			AIAgentFunctions.requestMessageForActor(orgasmData, "ext_nsfw_orgasm", orgasmer.GetDisplayName())
		else
			AIAgentFunctions.requestMessageForActor(orgasmer.GetDisplayName() + "^" + partnerName + "^" + sceneID + "^" + slOrgasmTags, "ext_nsfw_npc_orgasm", orgasmer.GetDisplayName())
		endif
	endif
EndFunction

Function OnSexLabAnimEnd(AIAgentNSFW bridge, int tid, bool HasPlayer) global
	if !AIAgentNSFWSceneEngine.UseSexLabEngine()
		return
	endif
	SexLabFramework SexLab = SexLabUtil.GetAPI()
	if (!SexLab)
		return
	endif
	sslThreadController controller = SexLab.GetController(tid)
	string score = ""
	if (controller)
		Actor[] actors = controller.Positions
		int i = actors.Length
		while (i > 0)
			i -= 1
			score = score + "/" + actors[i].GetDisplayName() + "@" + SexLab.GetEnjoyment(tid, actors[i])
			if (actors[i].GetFormID() != 0x14)
				AIAgentFunctions.setAnimationBusy(0, actors[i].GetDisplayName())
				AIAgentFunctions.setLocked(0, actors[i].GetDisplayName())
			endif
		endWhile
	endif

	; Insurance: if SexLab's controller was already gone, fall back to the stashed roster so teardown still fires.
	if score == ""
		score = bridge.BuildScoringFromStash(tid)
	endif

	AIAgentFunctions.logMessage("# END OF SEX SCENE", "infoaction")
	bridge.SendSceneEndWithHardSpeechFlush(score)
	bridge.ClearStashedNpcSceneActors(tid)
	AIAgentFunctions.logMessage("", "force_current_task")
EndFunction

Function QuickStartActors(Actor[] actorsInvolved, string slTag) global
			Actor slA2 = none
			Actor slA3 = none
			Actor slA4 = none
			Actor slA5 = none
			if (actorsInvolved.Length > 1)
				slA2 = actorsInvolved[1]
			endif
			if (actorsInvolved.Length > 2)
				slA3 = actorsInvolved[2]
			endif
			if (actorsInvolved.Length > 3)
				slA4 = actorsInvolved[3]
			endif
			if (actorsInvolved.Length > 4)
				slA5 = actorsInvolved[4]
			endif
			sslThreadController slc = SexLabUtil.QuickStart(actorsInvolved[0], slA2, slA3, slA4, slA5, none, "", slTag)
			if (!slc && slTag != "")
				; Tag found no matching animation in the player's pack - retry untagged so a scene still starts.
				slc = SexLabUtil.QuickStart(actorsInvolved[0], slA2, slA3, slA4, slA5, none, "", "")
			endif
			Debug.Trace("[CHIM-NSFW] Launched SexLab scene (tag="+slTag+", actors="+actorsInvolved.Length+")")
EndFunction

Function ShiftForActor(Actor npc, string npcname, string parameter) global
			SexLabFramework slfShift = SexLabUtil.GetAPI()
			if (slfShift)
				int slShiftTid = slfShift.FindActorController(npc)
				if (slShiftTid < 0)
					slShiftTid = slfShift.FindActorController(Game.GetPlayer())
				endif
				if (slShiftTid >= 0)
					bool slShifted = ShiftSexLabScene(slfShift, slShiftTid, parameter)
					Debug.Trace("[CHIM-NSFW] ExtCmdSexCommand (SexLab): act=" + parameter + " thread=" + slShiftTid + " shifted=" + slShifted)
					if slShifted
						AIAgentFunctions.logMessageForActor("command@ExtCmdSexCommand@"+parameter+"@ok: SexLab scene changed to the requested act","funcret",npcname)
					else
						int slCurrentTid = slfShift.FindActorController(npc)
						if slCurrentTid < 0
							slCurrentTid = slfShift.FindActorController(Game.GetPlayer())
						endif
						if slCurrentTid >= 0
							AIAgentFunctions.logMessageForActor("command@ExtCmdSexCommand@"+parameter+"@error: no requested SexLab replacement was confirmed; the current scene continues","funcret",npcname)
						else
							AIAgentFunctions.logMessageForActor("command@ExtCmdSexCommand@"+parameter+"@error: the requested SexLab replacement failed and no active scene remains","funcret",npcname)
						endif
					endif
				else
					Debug.Trace("[CHIM-NSFW] ExtCmdSexCommand: " + npc.GetDisplayName() + " is in neither an OStim nor a SexLab scene")
					AIAgentFunctions.logMessageForActor("command@ExtCmdSexCommand@"+parameter+"@error: no running SexLab scene was found for the requested change","funcret",npcname)
				endif
			else
				AIAgentFunctions.logMessageForActor("command@ExtCmdSexCommand@"+parameter+"@error: SexLab API is unavailable","funcret",npcname)
			endif
EndFunction

Function StopPlayerScene() global
		SexLabFramework SexLabStop = SexLabUtil.GetAPI()
		if (SexLabStop)
			int slTid = SexLabStop.FindActorController(Game.GetPlayer())
			if (slTid >= 0)
				sslThreadController slController = SexLabStop.GetController(slTid)
				if (slController)
					Debug.Trace("[CHIM-NSFW] Stopping player SexLab scene thread: " + slTid)
					slController.EndAnimation()
				endif
			endif
		endif
EndFunction

string Function ResolveSpeakerPartner(Actor speaker, int threadID) global
		SexLabFramework SexLab = SexLabUtil.GetAPI()
		if SexLab
			int tid = threadID
			if tid < 0
				tid = SexLab.FindActorController(speaker)
			endif
			if tid >= 0
				sslThreadController controller = SexLab.GetController(tid)
				if controller
					Actor[] pos = controller.Positions
					if pos
						int i = 0
						while i < pos.Length
							if pos[i] != None && pos[i] != speaker && pos[i] != Game.GetPlayer()
								return pos[i].GetDisplayName()
							endif
							i += 1
						endwhile
					endif
				endif
			endif
		endif
		return ""
EndFunction
