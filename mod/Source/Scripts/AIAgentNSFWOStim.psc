Scriptname AIAgentNSFWOStim Hidden
; Optional typed OStim API. The caller checks HasOStim before loading this script.
Actor Function GetSexPartner(Actor who) global
    OSexIntegrationMain ostim = Game.GetFormFromFile(0x000801, "Ostim.esp") as OSexIntegrationMain
    if ostim
        return ostim.GetSexPartner(who)
    endif
    return None
EndFunction
