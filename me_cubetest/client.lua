--[[
    TAOM -> RedM, Durchstichtest.

    Drei Tests, von billig nach teuer:

      /mestock                      findet ein brauchbares RDR2-Stock-Prop
      /meradius [start] [schritt] [max] [modell]
                                    misst den nutzbaren Weltradius
                                    -> laeuft mit Stock-Prop, braucht NICHTS Eigenes
      /mepad                        prueft die eigene Pipeline
                                    -> braucht ydr/ybn/ytyp in stream/

    Der Radiustest kommt bewusst zuerst: sein Ergebnis bestimmt den Maszstab
    der ganzen Karte, und er braucht kein einziges selbst gebautes Asset.

    Ausgabe landet in der F8-Konsole.
]]

local CUSTOM_MODEL = 'me_testpad'

-- Bestaetigte RDR2-Objektnamen. Falls keiner laedt: eigenen Namen an
-- /metest oder /meradius uebergeben, Listen gibt es auf redlookup.com.
local STOCK_CANDIDATES = {
    'p_door01x',
    'p_jug01x',
    'p_book02x',
    'p_bottlebeer01x',
    's_mp_moneybag02x',
}

local TEST_Z     = 1500.0   -- ueber der RDR2-Wasserebene
local FALL_LIMIT = 10.0     -- mehr Absacken = durchgefallen

local spawned = {}

local function log(fmt, ...)
    print(('[me_cubetest] ' .. fmt):format(...))
end

local function loadModel(name, timeoutMs)
    local hash = GetHashKey(name)
    RequestModel(hash)
    local t0 = GetGameTimer()
    while not HasModelLoaded(hash) do
        Wait(10)
        if GetGameTimer() - t0 > (timeoutMs or 8000) then
            return nil, GetGameTimer() - t0
        end
    end
    return hash, GetGameTimer() - t0
end

local function spawnAt(hash, x, y, z)
    local obj = CreateObject(hash, x + 0.0, y + 0.0, z + 0.0, false, false, false)
    if obj == 0 or not DoesEntityExist(obj) then return nil end
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, true, true)
    spawned[#spawned + 1] = obj
    return obj
end

local function findStock()
    for _, name in ipairs(STOCK_CANDIDATES) do
        local hash = loadModel(name, 3000)
        if hash then return name, hash end
    end
    return nil
end

--------------------------------------------------------------------------
--- Misst, was an einer Position noch funktioniert.
--- freezePlayer: bei kleinen Stock-Props sinnvoll - dort gibt es nichts zum
--- Draufstehen, und ein endlos fallender Spieler verrauscht die Messung.
--------------------------------------------------------------------------
local function probe(hash, x, y, z, freezePlayer)
    local ped = PlayerPedId()

    local obj = spawnAt(hash, x, y, z)
    if not obj then
        return { objectOk = false }
    end

    -- Wie genau speichert die Engine die Position? Reine Float-Praezision,
    -- waechst linear mit der Entfernung vom Nullpunkt.
    local op = GetEntityCoords(obj)
    local objDrift = math.max(math.abs(op.x - x), math.abs(op.y - y))

    SetEntityCoords(ped, x + 0.0, y + 0.0, z + 3.0, false, false, false, false)
    FreezeEntityPosition(ped, freezePlayer and true or false)

    Wait(2000)

    local pp      = GetEntityCoords(ped)
    local pedDrift = math.max(math.abs(pp.x - x), math.abs(pp.y - y))
    local drop     = (z + 3.0) - pp.z
    local stillThere = DoesEntityExist(obj)
    local visible    = stillThere and IsEntityVisible(obj)

    FreezeEntityPosition(ped, false)

    return {
        objectOk   = true,
        objDrift   = objDrift,
        pedDrift   = pedDrift,
        drop       = drop,
        fell       = (not freezePlayer) and drop > FALL_LIMIT,
        persists   = stillThere,
        visible    = visible,
    }
end

local function report(label, r)
    if not r.objectOk then
        log('%-10s CreateObject verweigert - harte Grenze erreicht.', label)
        return
    end
    log('%-10s Drift Objekt %.4f / Spieler %.4f m | existiert: %s | sichtbar: %s | Absacken %.2f m',
        label, r.objDrift, r.pedDrift, tostring(r.persists), tostring(r.visible), r.drop)
end

--------------------------------------------------------------------------
-- /mestock : brauchbares Stock-Prop suchen
--------------------------------------------------------------------------
RegisterCommand('mestock', function()
    CreateThread(function()
        log('Suche ein ladbares RDR2-Stock-Modell ...')
        for _, name in ipairs(STOCK_CANDIDATES) do
            local hash, ms = loadModel(name, 3000)
            log('  %-20s %s', name, hash and ('ok (%d ms)'):format(ms) or 'laedt nicht')
        end
        local name = findStock()
        if name then
            log('Nutze "%s" fuer /meradius.', name)
        else
            log('Keiner geladen. Eigenen Namen probieren: /metest <name>')
            log('Listen: redlookup.com/objects oder rdr2mods.com Objektliste.')
        end
    end)
end, false)

--------------------------------------------------------------------------
-- /metest <name> : einzelnen Modellnamen pruefen
--------------------------------------------------------------------------
RegisterCommand('metest', function(_, args)
    local name = args[1]
    if not name then log('Aufruf: /metest <modellname>'); return end
    CreateThread(function()
        local hash, ms = loadModel(name, 5000)
        if hash then
            log('"%s" geladen in %d ms (hash %d).', name, ms, hash)
        else
            log('"%s" laedt nicht (%d ms Timeout).', name, ms)
        end
    end)
end, false)

--------------------------------------------------------------------------
-- /meradius [start] [schritt] [max] [modell] : Weltradius ausmessen
--
-- Braucht kein eigenes Asset. Ohne Modellangabe wird erst das eigene
-- Testpad versucht, sonst ein Stock-Prop.
--------------------------------------------------------------------------
RegisterCommand('meradius', function(_, args)
    local startD = tonumber(args[1]) or 1000.0
    local stepD  = tonumber(args[2]) or 2000.0
    local maxD   = tonumber(args[3]) or 20000.0
    local wanted = args[4]

    CreateThread(function()
        local name, hash, isPad

        if wanted then
            hash = loadModel(wanted); name = wanted
        else
            hash = loadModel(CUSTOM_MODEL, 3000)
            if hash then
                name, isPad = CUSTOM_MODEL, true
            else
                name, hash = findStock()
            end
        end

        if not hash then
            log('Kein Modell verfuegbar. Erst /mestock laufen lassen.')
            return
        end
        log('Weltradius-Test mit "%s"%s', name, isPad and ' (eigenes Testpad)' or ' (Stock-Prop)')
        if not isPad then
            log('Kleines Prop: gemessen werden Praezision und Persistenz,')
            log('nicht ob es dich traegt. Dafuer braucht es /mepad.')
        end
        log('%.0f bis %.0f in Schritten von %.0f', startD, maxD, stepD)

        local lastGood, d = 0.0, startD
        while d <= maxD do
            local r = probe(hash, d, 0.0, TEST_Z, not isPad)
            report(('%.0f'):format(d), r)

            if not r.objectOk or not r.persists or r.fell then
                log('Grenze bei %.0f Units. Letzte saubere Distanz: %.0f.', d, lastGood)
                break
            end
            lastGood = d
            d = d + stepD
        end

        log('---')
        log('Nutzbarer Radius: rund %.0f Units.', lastGood)
        if lastGood > 0 then
            log('Das ergibt eine Welt von %.1f km Kantenlaenge.', lastGood * 2 / 1000)
            log('Fuer 1500 km Mittelerde => scale_horizontal %.5f in tools/config.json',
                (lastGood * 2) / 1500000.0)
        end
    end)
end, false)

--------------------------------------------------------------------------
-- /mepad : eigenes Testobjekt - prueft die Pipeline
--------------------------------------------------------------------------
RegisterCommand('mepad', function()
    CreateThread(function()
        log('Lade eigenes Modell "%s" ...', CUSTOM_MODEL)
        local hash, ms = loadModel(CUSTOM_MODEL)
        if not hash then
            log('FEHLGESCHLAGEN nach %d ms - wird nicht gestreamt.', ms)
            log('Pruefen: ydr/ybn/ytyp in stream/? Archetyp exakt "%s"?', CUSTOM_MODEL)
            log('Wirklich durch CitiCon konvertiert? Resource neu gestartet?')
            log('Gegenprobe, ob der Server ueberhaupt streamt: eine fertige')
            log('Community-Map einwerfen (siehe README).')
            return
        end
        log('Geladen in %d ms.', ms)

        local p = GetEntityCoords(PlayerPedId())
        local r = probe(hash, p.x, p.y, TEST_Z, false)
        report('mepad', r)

        if not r.objectOk then return end
        if r.fell then
            log('DURCHGEFALLEN - Modell laedt, aber die Collision traegt nicht.')
            log('Meist fehlt die ybn oder sie wurde nicht mitkonvertiert.')
            return
        end

        log('Du stehst drauf. Jetzt nachsehen:')
        log('  - Saeule bis Augenhoehe?      (1.83 m)')
        log('  - unter dem Torbogen durch?   (2.10 m licht)')
        log('  - Checker-Feld = 1 m          (jedes 10. Feld orange)')
        log('  - Rampen 15/30/45 Grad: ab wann rutschst du ab?')
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
    FreezeEntityPosition(PlayerPedId(), false)
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
    log('bereit.')
    log('  /mestock                                 Stock-Modell suchen')
    log('  /meradius [start] [schritt] [max] [modell]  Weltradius messen')
    log('  /mepad                                   eigene Pipeline pruefen')
    log('  /metest <name>   /mepos   /meclear')
end)
