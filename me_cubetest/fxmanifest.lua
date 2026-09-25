fx_version 'cerulean'
game 'rdr3'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'me_cubetest'
description 'TAOM -> RedM: Durchstichtest fuer Streaming, Collision und Weltradius'
version '1.0.0'

client_script 'client.lua'

-- So wie sie ist, laeuft die Resource sofort: /mestock und /meradius brauchen
-- kein eigenes Asset, sie nutzen RDR2-Stock-Props.
--
-- Erst wenn ydr/ybn/ytyp in stream/ liegen, die beiden Zeilen unten
-- einkommentieren - vorher zeigt ein data_file auf eine fehlende Datei und
-- die Resource startet nicht.

-- files {
--     'stream/me_testpad.ytyp',
-- }
--
-- data_file 'DLC_ITYP_REQUEST' 'stream/me_testpad.ytyp'
