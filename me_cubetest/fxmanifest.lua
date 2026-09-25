fx_version 'cerulean'
game 'rdr3'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'me_cubetest'
description 'TAOM -> RedM: Durchstichtest fuer Streaming, Collision und Weltradius'
version '1.0.0'

client_script 'client.lua'

-- Alles in stream/ wird automatisch gestreamt. Das ytyp zusaetzlich als
-- Archetyp-Request anmelden, sonst kennt die Engine das Modell nicht.
files {
    'stream/me_testpad.ytyp',
}

data_file 'DLC_ITYP_REQUEST' 'stream/me_testpad.ytyp'
