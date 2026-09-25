--[[
    TAOM -> RedM, Durchstichtest.

    Zwei Fragen, die vor jeder weiteren Arbeit beantwortet sein muessen:

      1. Laedt ein selbst gebautes Modell ueberhaupt, und traegt seine
         Collision den Spieler?   ->  /mepad
      2. Wie weit vom Nullpunkt funktioniert das noch?   ->  /meradius

    Ausgabe landet in der F8-Konsole.
]]

local MODEL      = GetHashKey('me_testpad')
local TEST_Z     = 1500.0   -- ueber der RDR2-Wasserebene, nichts wird verdeckt
local FALL_LIMIT = 10.0     -- mehr Absacken als das = durchgefallen

local spawned = {}

local function log(fmt, ...)
    print(('[me_cubetest] ' .. fmt):format(...))
end

local function loadModel(model, timeoutMs)
    RequestModel(model)
    local t0 = GetGameTimer()
    while not HasModelLoaded(model) do
        Wait(10)
        if GetGameTimer() - t0 > (timeoutMs or 10000) then
            return false, GetGameTimer() - t0
        end
    end
    return true, GetGameTimer() - t0
end

local function spawnPad(x, y, z)
    local obj = CreateObject(MODEL, x + 0.0, y + 0.0, z + 0.0, false, false, false)
    if obj == 0 or not DoesEntityExist(obj) then
        return nil
    end
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, true, true)
    spawned[#spawned + 1] = obj
    return obj
end

--- Setzt den Spieler an eine Position und misst, was danach passiert.
local function probe(x, y, z)
    local ped = PlayerPedId()
    SetEntityCoords(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false, false)

    -- Sofort zurueckgelesen: zeigt reine Float-Speichergenauigkeit,
    -- noch ohne Physik.
    local imm = GetEntityCoords(ped)
    local driftX = math.abs(imm.x - x)
    local driftY = math.abs(imm.y - y)

    Wait(2000)  -- Physik, Collision und Streaming Zeit geben

    local now    = GetEntityCoords(ped)
    local fell   = (z - now.z) > FALL_LIMIT
    local inAir  = IsEntityInAir(ped)

    local okGround, groundZ = false, 0.0
    local ok, a, b = pcall(GetGroundZFor_3dCoord, x + 0.0, y + 0.0, z + 0.0, false)
    if ok then okGround, groundZ = a, (b or 0.0) end

    return {
        drift    = math.max(driftX, driftY),
        restZ    = now.z,
        drop     = z - now.z,
        fell     = fell,
        inAir    = inAir,
        groundOk = okGround,
        groundZ  = groundZ,
    }
end

local function report(label, r)
    log('%-14s Drift %.4f m | Absacken %.2f m | in der Luft: %s | Ground-Z: %s',
        label, r.drift, r.drop, tostring(r.inAir),
        r.groundOk and ('%.2f'):format(r.groundZ) or 'nein')
    if r.fell then
        log('%-14s DURCHGEFALLEN - keine tragende Collision.', label)
    end
end

--------------------------------------------------------------------------
-- /mepad : Testobjekt beim Spieler absetzen und drauf stellen
--------------------------------------------------------------------------
RegisterCommand('mepad', function()
    CreateThread(function()
        log('Lade Modell me_testpad ...')
        local ok, ms = loadModel(MODEL)
        if not ok then
            log('FEHLGESCHLAGEN nach %d ms. Das Modell wird nicht gestreamt.', ms)
            log('Pruefen: liegen ydr/ybn/ytyp in stream/? Heiszt der Archetyp')
            log('im ytyp exakt "me_testpad"? Resource neu gestartet?')
            return
        end
        log('Modell geladen in %d ms.', ms)

        local p = GetEntityCoords(PlayerPedId())
        local obj = spawnPad(p.x, p.y, TEST_Z)
        if not obj then
            log('CreateObject fehlgeschlagen - Modell geladen, aber nicht platzierbar.')
            return
        end
        log('Objekt gesetzt auf z=%.1f. Teleportiere ...', TEST_Z)

        local r = probe(p.x, p.y, TEST_Z + 5.0)
        report('mepad', r)
        if not r.fell then
            log('Du stehst drauf. Jetzt nachsehen:')
            log('  - Saeule bis Augenhoehe?      (1.83 m)')
            log('  - unter dem Torbogen durch?   (2.10 m licht)')
            log('  - Checker-Feld = 1 m          (jedes 10. Feld orange)')
            log('  - Rampen 15/30/45 Grad: ab wann rutschst du ab?')
        end
    end)
end, false)

--------------------------------------------------------------------------
-- /meradius [start] [schritt] [max] : Weltradius ausmessen
--------------------------------------------------------------------------
RegisterCommand('meradius', function(_, args)
    local startD = tonumber(args[1]) or 1000.0
    local stepD  = tonumber(args[2]) or 2000.0
    local maxD   = tonumber(args[3]) or 20000.0

    CreateThread(function()
        if not loadModel(MODEL) then
            log('Modell nicht geladen - erst /mepad zum Laufen bringen.')
            return
        end

        log('Weltradius-Test: %.0f bis %.0f in Schritten von %.0f',
            startD, maxD, stepD)
        log('%-14s %s', 'Distanz', 'Ergebnis')

        local lastGood = 0.0
        local d = startD
        while d <= maxD do
            local obj = spawnPad(d, 0.0, TEST_Z)
            if not obj then
                log('%-14.0f CreateObject verweigert - harte Grenze.', d)
                break
            end
            local r = probe(d, 0.0, TEST_Z + 5.0)
            report(('%.0f'):format(d), r)
            if r.fell then
                log('Letzte tragende Distanz: %.0f Units.', lastGood)
                break
            end
            lastGood = d
            d = d + stepD
        end

        log('---')
        log('Nutzbarer Radius: rund %.0f Units.', lastGood)
        if lastGood > 0 then
            log('Daraus der Maszstab: 1500 km Mittelerde auf %.1f km Welt', lastGood * 2 / 1000)
            log('=> scale_horizontal ca. %.5f in tools/config.json',
                (lastGood * 2) / 1500000.0)
        end
    end)
end, false)

--------------------------------------------------------------------------
RegisterCommand('mepos', function()
    local p = GetEntityCoords(PlayerPedId())
    log('x=%.3f  y=%.3f  z=%.3f', p.x, p.y, p.z)
end, false)

RegisterCommand('meclear', function()
    local n = 0
    for _, obj in ipairs(spawned) do
        if DoesEntityExist(obj) then DeleteEntity(obj); n = n + 1 end
    end
    spawned = {}
    log('%d Objekte entfernt.', n)
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, obj in ipairs(spawned) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
end)

CreateThread(function()
    Wait(2000)
    log('bereit. Befehle: /mepad  /meradius [start] [schritt] [max]  /mepos  /meclear')
end)
