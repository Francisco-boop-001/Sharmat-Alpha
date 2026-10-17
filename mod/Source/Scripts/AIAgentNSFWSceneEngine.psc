Scriptname AIAgentNSFWSceneEngine Hidden
{NPC-initiated scene START / JOIN / group for OStim AND SexLab. All Global - no CK attachment needed; call as
 AIAgentNSFWSceneEngine.StartOrJoinScene(...). This is the EXECUTION helper only; AIAgentNSFW.CommandManager stays
 the entry point and delegates here (nothing orphaned). Scene selection is STEERED by the requested act (sceneAct)
 so the model reaches the full library by position/act instead of a random pick; it falls back to random/default
 when no tagged scene matches, so a scene always starts. Created 2026-06-29.}

; ============================================================
; ENGINE DETECTION
; ============================================================
bool Function HasSexLab() global
    return (Game.GetFormFromFile(0xD62, "SexLab.esm") as Quest) != None
EndFunction

bool Function HasOStim() global
    return (Game.GetFormFromFile(0x000801, "Ostim.esp") as Quest) != None
EndFunction



; PapyrusUtil JsonUtil root is Data/SKSE/Plugins/StorageUtilData/. Missing file = both on.
string Function SceneFrameworkFile() global
    return "SHARMAT_scene_framework"
EndFunction

bool Function DetectOStimScenes() global
    string f = SceneFrameworkFile()
    if !JsonUtil.JsonExists(f)
        return true
    endif
    return JsonUtil.GetPathIntValue(f, ".ostim", 1) != 0
EndFunction

bool Function DetectSexLabScenes() global
    string f = SceneFrameworkFile()
    if !JsonUtil.JsonExists(f)
        return true
    endif
    return JsonUtil.GetPathIntValue(f, ".sexlab", 1) != 0
EndFunction

bool Function UseOStimEngine() global
    return DetectOStimScenes() && HasOStim()
EndFunction

bool Function UseSexLabEngine() global
    return DetectSexLabScenes() && HasSexLab()
EndFunction

string Function AppendFwTag(string payload, string fw) global
    if fw == ""
        return payload
    endif
    if StringUtil.Find(payload, "fw=") >= 0
        return payload
    endif
    if payload == ""
        return "fw=" + fw
    endif
    if StringUtil.Find(payload, "^") >= 0
        return payload + "^fw=" + fw
    endif
    return payload + "/fw=" + fw
EndFunction

; ============================================================
; ACT -> ENGINE VOCAB. sceneAct is a normalized keyword from CommandManager:
; "vaginal" "anal" "oral" "handjob" "boobjob" or "" (empty = any/random). Each engine translates it into its own
; tag/action vocabulary so the same call steers either OStim or SexLab. Unknown/empty act -> "" (any scene).
; ============================================================
string Function OStimActionCSVForAct(string sceneAct) global
    if sceneAct == "vaginal"
        return "vaginalsex,vaginal,VaginalSex,Vaginal"
    elseif sceneAct == "anal"
        return "analsex,anal,AnalSex,Anal"
    elseif sceneAct == "oral"
        return "blowjob,cunnilingus,lickingpenis"
    elseif sceneAct == "handjob"
        return "handjob"
    elseif sceneAct == "boobjob"
        return "boobjob"
    elseif sceneAct == "masturbation"
        return "malemasturbation,femalemasturbation"
    endif
    return ""
EndFunction

; Some acts (e.g. massage) are not OStim "action types" but scene TAGS - resolve those here.
string Function OStimSceneTagForAct(string sceneAct) global
    if sceneAct == "massage"
        return "massage,foreplay,sensual"
    elseif sceneAct == "bloodfeed"
        ; vampire blood-feeding: matches OStim vampire-bite scenes (OARE_Devour*, OStim2P*VampireBite*).
        ; Include both the framework action name and common pack tags so the installed bite scenes resolve.
        return "vampirebite,vampire,bite,neckkissing,feeding,devour"
    elseif sceneAct == "kiss"
        return "kissing,frenchkissing"
    elseif sceneAct == "hug"
        return "cuddling,hugging,embrace"
    elseif sceneAct == "holdhands"
        return "holdinghands,handholding"
    endif
    return ""
EndFunction

; Chaste OARE staples by exact scene id - the tag pass can miss these (OARE_StandingHandHolding is
; tagged only "oare"), and the affection acts must NEVER fall through to a random (possibly sex) scene.
string Function OStimExactSceneForAct(string sceneAct) global
    if sceneAct == "kiss"
        return "OARE_StandingKiss"
    elseif sceneAct == "hug"
        return "OARE_StandingHug"
    elseif sceneAct == "holdhands"
        return "OARE_StandingHandHolding"
    endif
    return ""
EndFunction

; Affection and directed service acts must not fall through to unrelated sexual animations.
; This animation-selection rule is independent of actor-role sorting.
bool Function OStimActAvoidsSexualFallback(string sceneAct) global
    return sceneAct == "kiss" || sceneAct == "hug" || sceneAct == "holdhands" || sceneAct == "massage" || sceneAct == "bloodfeed" || StringUtil.Find(sceneAct, "frenchkissing") >= 0 || StringUtil.Find(sceneAct, "kissing") >= 0 || StringUtil.Find(sceneAct, "cuddling") >= 0 || StringUtil.Find(sceneAct, "hugging") >= 0 || StringUtil.Find(sceneAct, "holdinghands") >= 0
EndFunction

; Directed services retain giver/receiver order. Starting a kiss, hug or hand-hold
; does not itself choose the dominant animation slot.
bool Function OStimActPreservesServiceRoles(string sceneAct) global
    return sceneAct == "massage" || sceneAct == "bloodfeed"
EndFunction

bool Function OStimActIsChasteAffection(string sceneAct) global
    return sceneAct == "kiss" || sceneAct == "hug" || sceneAct == "holdhands"
EndFunction

bool Function ActorAppearsFemale(Actor akActor) global
    if akActor == None
        return false
    endif
    ActorBase base = akActor.GetActorBase()
    if base == None
        return false
    endif
    return base.GetSex() == 1
EndFunction

; Player + one NPC, both female. MakeLove/StartSex steers to vaginalsex first; that miss
; used to fall through to OStim's standing hub (OStim2PStandingCloseFF) instead of a lesbian act.
bool Function RosterIsPlayerFemaleFemalePair(Actor[] actors) global
    if actors.Length != 2 || actors[0] == None || actors[1] == None
        return false
    endif
    if actors.Find(Game.GetPlayer()) < 0
        return false
    endif
    return ActorAppearsFemale(actors[0]) && ActorAppearsFemale(actors[1])
EndFunction

string Function OStimLesbianActionCSV() global
    return "cunnilingus,vaginalfingering,fingering,tribbing,grinding"
EndFunction

string Function OStimLesbianTagCSV() global
    return "cunnilingus,tribbing,vaginalfingering,fingering"
EndFunction

; Prefer actual FF sex actions. A bare "lesbian" tag also matches idle hubs such as
; OStim2PStandingCloseFF, so reject idle/intro if we have to use that broader tag.
string Function OStimPickLesbianScene(Actor[] actors, string furnitureType = "") global
    bool hasFurniture = furnitureType != "" && furnitureType != "none"
    string sceneName = ""
    if hasFurniture
        sceneName = OLibrary.GetRandomFurnitureSceneWithAnyActionCSV(actors, furnitureType, OStimLesbianActionCSV())
    else
        sceneName = OLibrary.GetRandomSceneWithAnyActionCSV(actors, OStimLesbianActionCSV())
    endif
    if sceneName == ""
        if hasFurniture
            sceneName = OLibrary.GetRandomFurnitureSceneWithAnySceneTagCSV(actors, furnitureType, OStimLesbianTagCSV())
        else
            sceneName = OLibrary.GetRandomSceneWithAnySceneTagCSV(actors, OStimLesbianTagCSV())
        endif
    endif
    if sceneName == ""
        string tagged = ""
        if hasFurniture
            tagged = OLibrary.GetRandomFurnitureSceneWithAnySceneTagCSV(actors, furnitureType, "lesbian,Lesbian")
        else
            tagged = OLibrary.GetRandomSceneWithAnySceneTagCSV(actors, "lesbian,Lesbian")
        endif
        if tagged != "" && !OMetadata.HasAnySceneTagCSV(tagged, "idle,intro,Idle,Intro")
            sceneName = tagged
        endif
    endif
    return sceneName
EndFunction

bool Function IsProtectedMinorActor(Actor akActor) global
    if akActor == None
        return false
    endif
    if akActor.IsChild()
        return true
    endif
    ; Server-side exclusion/name checks remain authoritative. Keep the reported replacement-NPC
    ; case as a game-side last line of defense even when it uses an adult race/body.
    return akActor.GetDisplayName() == "Runa Fair-Shield"
EndFunction

bool Function RosterContainsProtectedMinor(Actor[] actors) global
    int i = 0
    while i < actors.Length
        if IsProtectedMinorActor(actors[i])
            return true
        endif
        i += 1
    endwhile
    return false
EndFunction

string Function RosterNames(Actor[] actors) global
    string names = ""
    int i = 0
    while i < actors.Length
        if i > 0
            names += ", "
        endif
        if actors[i] != None
            names += actors[i].GetDisplayName()
        else
            names += "<None>"
        endif
        i += 1
    endwhile
    return "[" + names + "]"
EndFunction

string Function SexLabTagsForAct(string sceneAct) global
    ; FIX 2026-07-11: accept BOTH the internal act keys (vaginal/anal/oral/...) AND the model-facing
    ; SexAction vocabulary (vaginalsex/analsex/blowjob/cunnilingus/frenchkissing/vaginalfingering).
    ; The old exact-match on internal keys made EVERY standard model SexAction a silent no-op on
    ; SexLab ("vaginalsex" never equals "vaginal"). Substring match mirrors the OStim sanitizer;
    ; order matters (vaginalfingering before vaginal). Tag lists are OR-matched downstream
    ; (GetAnimationsByTags RequireAll=false). Acts arrive lowercase from the tool enum.
    if StringUtil.Find(sceneAct, "vaginalfingering") >= 0
        return "Fingering,Vaginal"
    elseif StringUtil.Find(sceneAct, "vaginal") >= 0
        return "Vaginal"
    elseif StringUtil.Find(sceneAct, "anal") >= 0
        return "Anal"
    elseif StringUtil.Find(sceneAct, "blowjob") >= 0 || StringUtil.Find(sceneAct, "oral") >= 0
        return "Oral,Blowjob"
    elseif StringUtil.Find(sceneAct, "cunnilingus") >= 0
        return "Oral,Cunnilingus"
    elseif StringUtil.Find(sceneAct, "handjob") >= 0
        return "Handjob"
    elseif StringUtil.Find(sceneAct, "boobjob") >= 0 || StringUtil.Find(sceneAct, "titfuck") >= 0
        return "Boobjob"
    elseif StringUtil.Find(sceneAct, "frenchkissing") >= 0 || StringUtil.Find(sceneAct, "kissing") >= 0
        return "Kissing,Foreplay,LeadIn"
    elseif StringUtil.Find(sceneAct, "masturbation") >= 0
        return "Masturbation,Solo"
    elseif StringUtil.Find(sceneAct, "massage") >= 0
        return "Massage,Foreplay"
    elseif StringUtil.Find(sceneAct, "bloodfeed") >= 0
        return "Bite,Vampire,VampireFeed,Neck,Nibble,Feeding"
    endif
    return ""
EndFunction

; ============================================================
; PUBLIC ENTRY - start a scene between speaker+target, or (if one is already in a live scene and bAllowJoin)
; add the other into it (group / join via stop+restart with the combined actor list). sceneAct steers which
; position/animation is chosen. Returns true if handled.
; ============================================================
bool Function StartOrJoinScene(Actor akSpeaker, Actor akTarget, bool bAllowJoin = true, string sceneAct = "") global
    if akSpeaker == None || akTarget == None || akSpeaker == akTarget
        Debug.Trace("[CHIM-NSFW SceneEngine] StartOrJoinScene aborted: missing/identical actors")
        return false
    endif
    if UseOStimEngine()
        return StartOrJoinOStim(akSpeaker, akTarget, bAllowJoin, sceneAct)
    endif
    if UseSexLabEngine()
        return AIAgentNSFWSexLab.StartOrJoinSexLab(akSpeaker, akTarget, bAllowJoin, sceneAct)
    endif
    Debug.Trace("[CHIM-NSFW SceneEngine] No OStim or SexLab detected")
    return false
EndFunction

; ============================================================
; PUBLIC ENTRY - SOLO scene (e.g. self-masturbation) for a single actor. Returns true if handled.
; ============================================================
bool Function StartSoloScene(Actor akActor, string sceneAct = "") global
    if akActor == None
        Debug.Trace("[CHIM-NSFW SceneEngine] StartSoloScene aborted: missing actor")
        return false
    endif
    if UseOStimEngine()
        if OActor.GetSceneID(akActor) >= 0
            return true ; already in a scene
        endif
        Actor[] solo = new Actor[1]
        solo[0] = akActor
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim: starting solo scene " + akActor.GetDisplayName() + " act=" + sceneAct)
        return StartOStimScene(solo, sceneAct) >= 0
    endif
    if UseSexLabEngine()
        return AIAgentNSFWSexLab.StartSoloScene(akActor, sceneAct)
    endif
    return false
EndFunction

; ============================================================
; PUBLIC ENTRY - GROUP scene (fresh threesome+ in one call). actors[] may be oversized; count says how
; many leading slots are real. If any member is already in a live OStim scene, everyone merges into it
; (stop + restart with the combined roster). Returns true if a scene is running with the group.
; ============================================================
bool Function StartGroupScene(Actor[] actors, int count, string sceneAct = "") global
    if actors.Length < 1 || count < 2
        return false
    endif
    ; compact to an exact-size, None-free array (engine APIs expect clean rosters)
    if count > 5
        count = 5
    endif
    if count > actors.Length
        count = actors.Length
    endif
    Actor[] group = PapyrusUtil.ActorArray(0)
    int i = 0
    while i < count
        if actors[i] != None && group.Find(actors[i]) < 0
            group = PapyrusUtil.PushActor(group, actors[i])
        endif
        i += 1
    endwhile
    if group.Length < 2
        return false
    endif
    if UseOStimEngine()
        int liveThread = -1
        bool conflictingThreads = false
        i = 0
        while i < group.Length
            int actorThread = OActor.GetSceneID(group[i])
            if actorThread >= 0
                if liveThread < 0
                    liveThread = actorThread
                elseif actorThread != liveThread
                    conflictingThreads = true
                endif
            endif
            i += 1
        endwhile
        if conflictingThreads
            Debug.Trace("[CHIM-NSFW SceneEngine] OStim group merge aborted: requested actors belong to different live threads")
            return false
        endif
        if liveThread >= 0
            Actor[] combined = OThread.GetActors(liveThread)
            if combined.Length < 1
                Debug.Trace("[CHIM-NSFW SceneEngine] OStim group merge aborted: live thread " + liveThread + " returned no actors")
                return false
            endif
            bool mergeOverflow = false
            i = 0
            while i < group.Length
                if combined.Find(group[i]) < 0
                    if combined.Length < 5
                        combined = PapyrusUtil.PushActor(combined, group[i])
                    else
                        mergeOverflow = true
                    endif
                endif
                i += 1
            endwhile
            if mergeOverflow
                Debug.Trace("[CHIM-NSFW SceneEngine] OStim group merge aborted: combined roster exceeds five actors")
                return false
            endif
            Debug.Trace("[CHIM-NSFW SceneEngine] OStim: group merge into thread " + liveThread + " -> " + combined.Length + " actors")
            if !StopOStimThreadAndWait(liveThread, combined)
                return false
            endif
            return StartOStimScene(combined, sceneAct) >= 0
        endif
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim: fresh group scene with " + group.Length + " actors, act=" + sceneAct)
        return StartOStimScene(group, sceneAct, true) >= 0
    endif
    if UseSexLabEngine()
        return AIAgentNSFWSexLab.StartGroupScene(group, sceneAct)
    endif
    return false
EndFunction

; ============================================================
; PUBLIC ENTRY - one actor LEAVES their running scene; the remaining actors continue. Neither engine has a
; remove-actor API, so this is stop + restart minus the leaver. A couple scene simply ends (nobody remains
; to continue). Returns true if the leaver is out (whether or not a scene continues).
; ============================================================
bool Function LeaveScene(Actor akLeaver) global
    if akLeaver == None
        return false
    endif
    if HasOStim()
        int tid = OActor.GetSceneID(akLeaver)
        if tid < 0
            if HasSexLab()
                return AIAgentNSFWSexLab.LeaveScene(akLeaver)
            endif
            return false
        endif
        Actor[] current = OThread.GetActors(tid)
        if !StopOStimThreadAndWait(tid, current)
            return false
        endif
        if current.Length <= 2
            return true ; couple scene: leaving ends it
        endif
        Actor[] rest = PapyrusUtil.ActorArray(0)
        int i = 0
        while i < current.Length
            if current[i] != None && current[i] != akLeaver
                rest = PapyrusUtil.PushActor(rest, current[i])
            endif
            i += 1
        endwhile
        if rest.Length < 2
            return true
        endif
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim: " + akLeaver.GetDisplayName() + " left; restarting with " + rest.Length + " actors")
        return StartOStimScene(rest, "") >= 0
    endif
    if HasSexLab()
        return AIAgentNSFWSexLab.LeaveScene(akLeaver)
    endif
    return false
EndFunction

; ============================================================
; OSTIM
; ============================================================
bool Function StartOrJoinOStim(Actor akSpeaker, Actor akTarget, bool bAllowJoin, string sceneAct = "") global
    int speakerThread = OActor.GetSceneID(akSpeaker)
    int targetThread = OActor.GetSceneID(akTarget)
    int activeThread = speakerThread
    if activeThread < 0
        activeThread = targetThread
    endif

    if activeThread < 0
        ; neither is in a scene -> brand new scene with both, steered by sceneAct
        Actor[] pair = new Actor[2]
        pair[0] = akSpeaker
        pair[1] = akTarget
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim: starting new scene " + akSpeaker.GetDisplayName() + " + " + akTarget.GetDisplayName() + " act=" + sceneAct)
        return StartOStimScene(pair, sceneAct, true) >= 0
    endif

    if speakerThread >= 0 && targetThread >= 0 && speakerThread != targetThread
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim join aborted: actors belong to different live threads (" + speakerThread + ", " + targetThread + ")")
        return false
    endif

    ; Both already in the SAME scene -> SHIFT the current scene to the requested act (e.g. she's asked for a blowjob
    ; while you're mid-hug/kiss). Without this, a Start* act on two actors already together was a no-op and the scene
    ; never changed - the "asked for a BJ but stayed hugging" bug.
    if speakerThread >= 0 && targetThread >= 0 && speakerThread == targetThread
        if sceneAct != ""
            return ShiftOStimSceneToAct(speakerThread, sceneAct)
        endif
        return true
    endif

    if !bAllowJoin
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim: scene live but joining disabled")
        return false
    endif

    ; one of them is already in a live scene -> the OTHER one joins it (group)
    Actor joiner = akSpeaker
    if speakerThread >= 0
        joiner = akTarget
    endif
    Debug.Trace("[CHIM-NSFW SceneEngine] OStim: joining thread " + activeThread + " with " + joiner.GetDisplayName())
    return AddActorToOStimThread(activeThread, joiner)
EndFunction

int Function StartOStimScene(Actor[] actors, string sceneAct = "", bool allowRoleSelect = false, string forcedScene = "", ObjectReference forcedFurniture = None) global
    if RosterContainsProtectedMinor(actors)
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim start blocked: protected minor in actor roster")
        return -1
    endif
    ; OStim assigns animation roles by array position. Resolve the actual roster before selecting a
    ; pinned animation because a builder with a starting animation does not perform another sort.
    actors = ResolveOStimActorOrder(actors, sceneAct, allowRoleSelect)
    if actors.Length < 1 || actors[0] == None
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim start aborted: actor-role resolution failed")
        return -1
    endif
    ; NPC-ONLY FURNITURE FIX (2026-07-16, shonohmercy's report): OStim's NPC thread starter
    ; (NPCThreadStarter.cpp) auto-grabs the nearest furniture per MCM and HARD-FAILS the whole scene
    ; ("no starting node found", return -1) when no animation fits that furniture + this roster -
    ; the availability check counts nodes coarsely, the real lookup also filters by actor sexes /
    ; noRandomSelection / transitions. Player starts have a smarter flow, which is why only NPC-NPC
    ; scenes die near non-bed furniture. Bypass the broken branch by choosing furniture AND a
    ; matching animation OURSELVES: with both provided, the engine skips its own lookup entirely,
    ; and NPC threads drive furniture fine (only camera fades are player-gated in the engine).
    ; Pass 0 prefers beds (the long-proven case), pass 1 takes any other type with usable content;
    ; nothing usable nearby -> furniture OFF and a ground scene. Never a dead start.
    ; Affection/service staples stay furniture-free (their pinned OARE scenes are ground scenes).
    bool npcOnlyThread = actors.Find(Game.GetPlayer()) < 0
    ObjectReference npcFurnRef = forcedFurniture
    string sceneName = forcedScene
    if sceneName == "" && npcFurnRef == None && npcOnlyThread && !OStimActAvoidsSexualFallback(sceneAct)
        ObjectReference[] furnCands = OFurniture.FindFurniture(actors.Length, actors[0], 1000.0, 96.0)
        string furnTagCSV = OStimSceneTagForAct(sceneAct)
        int fPass = 0
        while fPass < 2 && npcFurnRef == None
            int fi = 0
            while fi < furnCands.Length && npcFurnRef == None
                ObjectReference cand = furnCands[fi]
                if cand != None
                    string fType = OFurniture.GetFurnitureType(cand)
                    if fType != "" && fType != "none" && (fPass == 1 || fType == "bed")
                        string fScene = ""
                        if furnTagCSV != ""
                            fScene = OLibrary.GetRandomFurnitureSceneWithAnySceneTagCSV(actors, fType, furnTagCSV)
                        endif
                        if fScene == ""
                            fScene = OLibrary.GetRandomFurnitureScene(actors, fType)
                        endif
                        if fScene != ""
                            npcFurnRef = cand
                            sceneName = fScene
                        endif
                    endif
                endif
                fi += 1
            endwhile
            fPass += 1
        endwhile
    endif
    bool chasteAffection = OStimActIsChasteAffection(sceneAct)
    if sceneName == "" && chasteAffection
        ; Exact-first and fail-closed: broad tags such as "cuddling" can include sexual scenes.
        sceneName = OStimExactSceneForAct(sceneAct)
    endif
    if sceneName == "" && !chasteAffection
        string actionCSV = OStimActionCSVForAct(sceneAct)
        if actionCSV != ""
            sceneName = OLibrary.GetRandomSceneWithAnyActionCSV(actors, actionCSV)
        endif
    endif
    if sceneName == "" && !chasteAffection
        string tagCSV = OStimSceneTagForAct(sceneAct)
        if tagCSV != ""
            sceneName = OLibrary.GetRandomSceneWithAnySceneTagCSV(actors, tagCSV)
        endif
    endif
    if sceneName == "" && !chasteAffection
        sceneName = OStimExactSceneForAct(sceneAct) ; affection acts pin their OARE staple, never a random scene
    endif
    if sceneName == "" && !OStimActAvoidsSexualFallback(sceneAct) && RosterIsPlayerFemaleFemalePair(actors)
        string fallbackFurnitureType = ""
        if npcFurnRef != None
            fallbackFurnitureType = OFurniture.GetFurnitureType(npcFurnRef)
        endif
        sceneName = OStimPickLesbianScene(actors, fallbackFurnitureType)
        if sceneName != ""
            Debug.Trace("[CHIM-NSFW SceneEngine] OStim FF player pair: using lesbian start " + sceneName + " instead of hub fallback")
        endif
    endif
    if sceneName == "" && chasteAffection
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim affection start aborted: no exact chaste scene for act=" + sceneAct)
        return -1
    elseif sceneName == ""
        sceneName = OLibrary.GetRandomScene(actors) ; fallback: any valid scene for this actor set
    endif
    int builderID = OThreadBuilder.Create(actors)
    if builderID < 0
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim start aborted: invalid actor roster " + RosterNames(actors))
        return -1
    endif
    if sceneName != ""
        OThreadBuilder.SetStartingAnimation(builderID, sceneName)
    endif
    if npcFurnRef != None
        OThreadBuilder.SetFurniture(builderID, npcFurnRef)
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim start: pinned " + OFurniture.GetFurnitureType(npcFurnRef) + " furniture with matching scene " + sceneName + " (" + RosterNames(actors) + ")")
    elseif npcOnlyThread
        OThreadBuilder.NoFurniture(builderID)
        Debug.Trace("[CHIM-NSFW SceneEngine] NPC-only thread: no furniture with usable animations nearby - ground scene (" + RosterNames(actors) + ")")
    endif
    return OThreadBuilder.Start(builderID)
EndFunction

bool Function AddActorToOStimThread(int threadID, Actor joiner) global
    if joiner == None
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim join aborted: joiner is missing")
        return false
    endif
    Actor[] current = OThread.GetActors(threadID)
    if current.Length < 1 || current.Length >= 5
        return false
    endif
    if current.Find(joiner) >= 0
        return true ; already in this scene - nothing to do (e.g. StartSex when already partnered)
    endif
    if OActor.GetSceneID(joiner) >= 0
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim join aborted: joiner already belongs to a different live thread")
        return false
    endif
    Actor[] combined = PapyrusUtil.PushActor(current, joiner)
    if !StopOStimThreadAndWait(threadID, combined)
        return false
    endif
    return StartOStimScene(combined, "") >= 0
EndFunction

; Resolve and perform an in-thread OStim act change. Callers may supply an exact action vocabulary
; and furniture type; this keeps command-specific scene filtering inside the same role-safe path.
; Returns the confirmed resulting thread ID, or -1 when no requested scene was confirmed.
int Function TransitionOStimSceneToAct(int threadID, string sceneAct, string requestedActionCSV = "", string requestedFurnitureType = "") global
    Actor[] actors = OThread.GetActors(threadID)
    if actors.Length < 1
        return -1
    endif
    Actor[] desiredOrder = ResolveOStimActorOrder(actors, sceneAct, false)
    if desiredOrder.Length != actors.Length || desiredOrder.Length < 1
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim shift aborted: actor-role resolution failed for act=" + sceneAct)
        return -1
    endif

    string furnitureType = requestedFurnitureType
    if furnitureType == ""
        furnitureType = OThread.GetFurnitureType(threadID)
    endif
    bool hasFurniture = furnitureType != "" && furnitureType != "none"

    string sceneName = ""
    bool chasteAffection = OStimActIsChasteAffection(sceneAct)
    if chasteAffection && !hasFurniture && desiredOrder.Length == 2
        sceneName = OStimExactSceneForAct(sceneAct)
    endif
    string actionCSV = requestedActionCSV
    if actionCSV == ""
        actionCSV = OStimActionCSVForAct(sceneAct)
    endif
    if sceneName == "" && !chasteAffection && actionCSV != ""
        if hasFurniture
            sceneName = OLibrary.GetRandomFurnitureSceneWithAnyActionCSV(desiredOrder, furnitureType, actionCSV)
        else
            sceneName = OLibrary.GetRandomSceneWithAnyActionCSV(desiredOrder, actionCSV)
        endif
    endif
    if sceneName == "" && !chasteAffection
        string tagCSV = OStimSceneTagForAct(sceneAct)
        if tagCSV != ""
            if hasFurniture
                sceneName = OLibrary.GetRandomFurnitureSceneWithAnySceneTagCSV(desiredOrder, furnitureType, tagCSV)
            else
                sceneName = OLibrary.GetRandomSceneWithAnySceneTagCSV(desiredOrder, tagCSV)
            endif
        endif
    endif
    if sceneName == "" && !chasteAffection && !hasFurniture && desiredOrder.Length == 2
        sceneName = OStimExactSceneForAct(sceneAct) ; e.g. shift a hug to hand-holding (tagged only "oare")
    endif
    if sceneName == "" && !OStimActAvoidsSexualFallback(sceneAct) && RosterIsPlayerFemaleFemalePair(desiredOrder)
        sceneName = OStimPickLesbianScene(desiredOrder, furnitureType)
        if sceneName != ""
            Debug.Trace("[CHIM-NSFW SceneEngine] OStim FF player pair shift: using lesbian scene " + sceneName)
        endif
    endif
    if sceneName == ""
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim shift: no scene matched act=" + sceneAct + " - leaving current scene")
        return -1
    endif

    if OStimActorOrderMatches(actors, desiredOrder)
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim shift: thread " + threadID + " -> " + sceneName + " (act=" + sceneAct + ", actor order unchanged)")
        OThread.WarpTo(threadID, sceneName, true)
        int warpGuard = 0
        while warpGuard < 50 && OThread.IsRunning(threadID) && OThread.GetScene(threadID) != sceneName
            Utility.Wait(0.2)
            warpGuard += 1
        endwhile
        if OThread.IsRunning(threadID) && OThread.GetScene(threadID) == sceneName
            return threadID
        endif
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim shift failed verification: requested " + sceneName + ", current " + OThread.GetScene(threadID))
        return -1
    endif

    ObjectReference currentFurniture = None
    if hasFurniture
        currentFurniture = OThread.GetFurniture(threadID)
        if currentFurniture == None
            Debug.Trace("[CHIM-NSFW SceneEngine] OStim shift restart aborted: furniture type " + furnitureType + " has no live furniture reference")
            return -1
        endif
    endif
    Debug.Trace("[CHIM-NSFW SceneEngine] OStim shift requires role reorder: " + RosterNames(actors) + " -> " + RosterNames(desiredOrder) + "; restarting thread " + threadID)
    if !StopOStimThreadAndWait(threadID, actors)
        return -1
    endif
    if !OStimRosterIsReleased(desiredOrder)
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim shift restart aborted: desired actors are no longer available")
        return -1
    endif
    int newThreadID = StartOStimScene(desiredOrder, sceneAct, false, sceneName, currentFurniture)
    if newThreadID < 0
        return -1
    endif

    int guard = 0
    while guard < 50 && (!OThread.IsRunning(newThreadID) || OThread.GetScene(newThreadID) != sceneName)
        Utility.Wait(0.2)
        guard += 1
    endwhile
    if OThread.IsRunning(newThreadID) && OThread.GetScene(newThreadID) == sceneName
        return newThreadID
    endif
    Debug.Trace("[CHIM-NSFW SceneEngine] OStim restart failed verification: requested " + sceneName + ", current " + OThread.GetScene(newThreadID))
    return -1
EndFunction

bool Function ShiftOStimSceneToAct(int threadID, string sceneAct) global
    return TransitionOStimSceneToAct(threadID, sceneAct) >= 0
EndFunction

; ============================================================
; SHARED ROLE / TEARDOWN HELPERS
; ============================================================


; One authority for OStim actor-slot policy. Affection and sexual scenes use OStim sorting;
; directed services retain giver/receiver order. Anatomy, Always Dominant/Submissive, and the
; optional fresh-scene role picker retain framework behavior. Existing-thread transitions pass
; allowRoleSelect=false: they must never open a second role prompt while a scene is already active.
Actor[] Function ResolveOStimActorOrder(Actor[] actors, string sceneAct = "", bool allowRoleSelect = false) global
    if actors.Length < 2 || OStimActPreservesServiceRoles(sceneAct)
        return actors
    endif

    Actor[] invalid = PapyrusUtil.ActorArray(0)
    Actor[] noDoms = PapyrusUtil.ActorArray(0)
    Actor[] sorted
    if allowRoleSelect && actors.Find(Game.GetPlayer()) >= 0
        sorted = OActorUtil.SelectIndexAndSort(actors, noDoms)
    else
        sorted = OActorUtil.Sort(actors, noDoms, -1)
    endif

    if sorted.Length != actors.Length
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim role sort failed: returned " + sorted.Length + " of " + actors.Length + " actors; aborting scene")
        return invalid
    endif

    int i = 0
    while i < sorted.Length
        if sorted[i] == None || actors.Find(sorted[i]) < 0 || sorted.Find(sorted[i]) != i
            Debug.Trace("[CHIM-NSFW SceneEngine] OStim role sort returned an invalid roster; aborting scene")
            return invalid
        endif
        i += 1
    endwhile

    Debug.Trace("[CHIM-NSFW SceneEngine] OStim role order: " + RosterNames(actors) + " -> " + RosterNames(sorted) + " (slot 0 = dominant/active)")
    return sorted
EndFunction

bool Function OStimActorOrderMatches(Actor[] current, Actor[] desired) global
    if current.Length != desired.Length
        return false
    endif
    int i = 0
    while i < current.Length
        if current[i] != desired[i]
            return false
        endif
        i += 1
    endwhile
    return true
EndFunction

bool Function OStimRosterIsReleased(Actor[] actors) global
    int i = 0
    while i < actors.Length
        if actors[i] == None || OActor.GetSceneID(actors[i]) >= 0
            return false
        endif
        i += 1
    endwhile
    return true
EndFunction

; A restart is allowed only after both the thread and every actor mapping have been released. A
; timeout aborts instead of starting an overlapping thread with actors still owned by the old one.
bool Function StopOStimThreadAndWait(int threadID, Actor[] actors) global
    OThread.Stop(threadID)
    int guard = 0
    while guard < 50 && (OThread.IsRunning(threadID) || !OStimRosterIsReleased(actors))
        Utility.Wait(0.2)
        guard += 1
    endwhile
    if OThread.IsRunning(threadID) || !OStimRosterIsReleased(actors)
        Debug.Trace("[CHIM-NSFW SceneEngine] OStim restart aborted: thread " + threadID + " did not release its actors")
        return false
    endif
    return true
EndFunction



; SexLab teardown is asynchronous. Do not start a replacement until every requested actor has left
; its controller; a timeout is a hard failure so two controllers can never claim the same actor.


; ============================================================
; SEXLAB
; ============================================================






; Shift the CURRENT SexLab scene (same actors) to the requested act. SexLab has NO in-thread position swap (no
; OThread.WarpTo equivalent), so this does a quick EndAnimation + StartSex restart with animations matching the new
; act. If no animation matches, it leaves the current scene running (no pointless teardown) - mirroring the OStim
; ShiftOStimSceneToAct "leave current scene on miss" behaviour.


int Function CountMales(Actor[] actors) global
    int males = 0
    int i = 0
    while i < actors.Length
        if actors[i] != None && actors[i].GetActorBase() != None && actors[i].GetActorBase().GetSex() == 0
            males += 1
        endif
        i += 1
    endwhile
    return males
EndFunction
